#!/bin/sh

# Don't use set -e globally, but check critical operations explicitly

# Function to handle cleanup and exit
cleanup_and_exit() {
	exit_code="$1"
	error_msg="$2"

	echo ""
	echo "CRITICAL ERROR: $error_msg"
	echo "Template generation aborted to prevent further damage."
	echo ""

	# Clean up any temp files
	rm -f /root/templates/prod-*.qcow2 2>/dev/null || true

	exit "$exit_code"
}

# Function to check critical prerequisites
check_prerequisites() {
	# Check if we can access Ceph
	if ! ceph -s >/dev/null 2>&1; then
		cleanup_and_exit 1 "Cannot access Ceph cluster"
	fi

	# Check if storage pool exists
	if ! rbd ls ceph >/dev/null 2>&1; then
		cleanup_and_exit 1 "Cannot access RBD pool 'ceph'"
	fi

	# Check if we have required directories
	if [ ! -d "$ISODIR" ]; then
		cleanup_and_exit 1 "ISO directory $ISODIR does not exist"
	fi

	echo "✓ Prerequisites check passed"
}

BASEDIR=/root/templates
TEMPLATES='./templates.csv'
ISODIR='/mnt/pve/luggage/template/iso'
STORAGE=${STORAGE:-ceph}              # Allow override with: STORAGE=local-lvm ./template-generate.sh
FORCE_REBUILD=${FORCE_REBUILD:-false} # Set FORCE_REBUILD=true to rebuild templates that already exist
PW=$(cat ./config)

# ID Calculation Functions - KFVEE format
# K=Kernel (1=Linux,2=Windows), F=Family(0-9), V=Version(0-9), EE=Instance(00-99)
calculate_base_id() {
	name="$1"
	version="$2"

	case "$name" in
	# Red Hat Family (F=1): RHEL, CentOS, Rocky, Alma, Oracle
	"RedHat")
		case "$version" in
		7) echo 1110 ;;
		8) echo 1120 ;;
		9) echo 1130 ;;
		*) echo 1190 ;;
		esac
		;;
	"CentOS")
		case "$version" in
		6) echo 1140 ;;
		7) echo 1150 ;;
		Stream) echo 1160 ;;
		*) echo 1190 ;;
		esac
		;;
	"Rocky")
		case "$version" in
		8) echo 1170 ;;
		9) echo 1180 ;;
		*) echo 1190 ;;
		esac
		;;
	"Alma")
		case "$version" in
		8) echo 1110 ;; # Reuse RHEL 7 slot since similar
		9) echo 1120 ;; # Reuse RHEL 8 slot since similar
		*) echo 1190 ;;
		esac
		;;
	"Oracle")
		case "$version" in
		7) echo 1170 ;; # Reuse Rocky 8 slot
		8) echo 1180 ;; # Reuse Rocky 9 slot
		9) echo 1130 ;; # Reuse RHEL 9 slot
		*) echo 1190 ;;
		esac
		;;

	# Debian Family (F=2): Debian, Ubuntu
	"Debian")
		case "$version" in
		11) echo 1210 ;;
		12) echo 1220 ;;
		*) echo 1290 ;;
		esac
		;;
	"Ubuntu")
		case "$version" in
		2004) echo 1230 ;;
		2204) echo 1240 ;;
		2404) echo 1250 ;;
		*) echo 1290 ;;
		esac
		;;

	# SUSE Family (F=3): OpenSUSE, SLES
	"OpenSUSE")
		case "$version" in
		15.6) echo 1310 ;;
		*) echo 1390 ;;
		esac
		;;
	"SLES")
		case "$version" in
		15) echo 1320 ;;
		*) echo 1390 ;;
		esac
		;;

	# Arch Family (F=4)
	"Arch") echo 1410 ;;

	# Amazon Family (F=5)
	"AmazonLinux")
		case "$version" in
		2) echo 1510 ;;
		*) echo 1590 ;;
		esac
		;;

	# Fedora Family (F=6)
	"Fedora")
		case "$version" in
		36) echo 1610 ;;
		40) echo 1620 ;;
		*) echo 1690 ;;
		esac
		;;

	# Windows Family (K=2, F=1)
	"Windows")
		case "$version" in
		2022) echo 2110 ;;
		*) echo 2190 ;;
		esac
		;;

	*) echo 1990 ;; # Unknown Linux
	esac
}

# URL Discovery Functions
get_ubuntu_codename() {
	case $1 in
	2004) echo "focal" ;;
	2204) echo "jammy" ;;
	2404) echo "noble" ;;
	*) return 1 ;;
	esac
}

get_dynamic_url() {
	name="$1"
	version="$2"
	fallback_url="$3"
	fallback_iso="$4"

	case "$name-$version" in
	"Rocky-8" | "Rocky-9")
		echo "https://dl.rockylinux.org/pub/rocky/$version/images/x86_64/"
		echo "Rocky-$version-GenericCloud-Base.latest.x86_64.qcow2"
		return 0
		;;
	"Alma-8" | "Alma-9")
		echo "https://repo.almalinux.org/almalinux/$version/cloud/x86_64/images/"
		echo "AlmaLinux-$version-GenericCloud-latest.x86_64.qcow2"
		return 0
		;;
	"CentOS-Stream")
		echo "https://cloud.centos.org/centos/9-stream/x86_64/images/"
		echo "CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
		return 0
		;;
	"Fedora-"*)
		echo "https://download.fedoraproject.org/pub/fedora/linux/releases/$version/Cloud/x86_64/images/"
		echo "Fedora-Cloud-Base-Generic.x86_64-$version-1.2.qcow2"
		return 0
		;;
	"Ubuntu-"*)
		if ! codename=$(get_ubuntu_codename "$version"); then
			echo "https://cloud-images.ubuntu.com/$codename/current/"
			echo "$codename-server-cloudimg-amd64.img"
			return 0
		fi
		;;
	esac

	# Fallback to CSV values
	echo "$fallback_url"
	echo "$fallback_iso"
	return 1
}

if [ ! -f "${TEMPLATES}" ]; then
	echo "Couldn't find ${TEMPLATES} : exiting" >&2
	exit 1
fi

if [ ! -d "${ISODIR}" ]; then
	echo "Couldn't find ${ISODIR} : exiting" >&2
	exit 1
fi

# Function to process a single template
process_template() {
	LINE="$1"
	NAME=$(echo "$LINE" | awk -F, '{print $1}')
	LCNAME=$(echo "$NAME" | tr "[:upper:]" "[:lower:]")
	VER=$(echo "$LINE" | awk -F, '{print $2}')

	# Calculate template ID
	BASE_ID=$(calculate_base_id "$NAME" "$VER")
	TPROD=$((BASE_ID * 10))

	# Skip templates that already exist unless a rebuild is explicitly forced.
	# This runs before the ISO download and virt-customize, so a warm host only
	# pays for templates that are actually missing. Set FORCE_REBUILD=true to
	# refresh a template that already exists (for example after an upstream image
	# update).
	if [ "${FORCE_REBUILD}" != "true" ] && qm status "${TPROD}" >/dev/null 2>&1; then
		echo "  ✓ Template ${TPROD} (template-${NAME}-${VER}) already exists - skipping"
		return
	fi

	# CSV parsing (Name,Version,URL,ISO)
	CSV_URL=$(echo "$LINE" | awk -F, '{print $3}')
	CSV_ISO=$(echo "$LINE" | awk -F, '{print $4}')

	# Get dynamic URL or fallback to CSV
	DYNAMIC_RESULT=$(get_dynamic_url "$NAME" "$VER" "$CSV_URL" "$CSV_ISO")
	URL=$(echo "$DYNAMIC_RESULT" | head -n1)
	ISO=$(echo "$DYNAMIC_RESULT" | tail -n1)

	if [ -z "${ISO}" ]; then
		echo "  ✗ No ISO definition - skipping"
		return
	fi

	if [ ! -f "${ISODIR}/${ISO}" ]; then
		echo "  → Downloading ${ISO}..."
		wget -q "${URL}${ISO}" -O "${ISODIR}/${ISO}" || {
			echo "  ✗ Download failed"
			return
		}
	fi

	TMPISO="${BASEDIR}/prod-${ISO}"

	echo "  → Customizing image (ID: $TPROD)..."
	cp "${ISODIR}/${ISO}" "${TMPISO}"

	# Build virt-customize command with batched operations
	VIRT_CMD="virt-customize -a $TMPISO"

	# Package installation (skip for RedHat due to subscription requirements)
	if [ "${NAME}" != "RedHat" ]; then
		PACKAGES="qemu-guest-agent,unzip"
		if [ "${NAME}" = "Debian" ]; then
			PACKAGES="${PACKAGES},gnupg"
		fi
		VIRT_CMD="${VIRT_CMD} --install ${PACKAGES}"
	fi

	# SELinux configuration
	if [ "${VER}" = "9" ] || [ "${VER}" = 8 ] || [ "${VER}" = "Stream" ]; then
		VIRT_CMD="${VIRT_CMD} --edit /etc/sysconfig/selinux:s/enforcing/disabled/"
	fi

	# Machine ID and random seed cleanup (all systems)
	VIRT_CMD="${VIRT_CMD} --truncate /etc/machine-id"
	VIRT_CMD="${VIRT_CMD} --run-command 'rm -f /var/lib/dbus/machine-id'"

	# Additional cleanup for Debian-based systems
	if [ "${NAME}" = "Debian" ] || [ "${NAME}" = "Ubuntu" ]; then
		VIRT_CMD="${VIRT_CMD} --run-command 'rm -f /var/lib/systemd/random-seed /var/lib/urandom/random-seed'"
	fi

	# Execute single batched virt-customize command (suppress output)
	eval "$VIRT_CMD" >/dev/null 2>&1

	# Destroy the existing template before rebuilding. We only reach this point
	# when the template did not exist, or when FORCE_REBUILD=true, so this is the
	# forced-refresh path (the early skip above handles the default warm case).
	if qm status ${TPROD} >/dev/null 2>&1; then
		echo "  → Destroying existing template ${TPROD} (force rebuild)..."
		qm destroy ${TPROD} --destroy-unreferenced-disks 1 >/dev/null 2>&1 || {
			echo "  ✗ Could not destroy template ${TPROD}, it may be in use"
			return
		}
	fi

	echo "  → Creating VM ${TPROD}..."
	if ! qm create ${TPROD} --memory 1024 --core 2 --name template-"${NAME}"-"${VER}" --net0 virtio,bridge=vmbr1 --pool Templates --cpu cputype=host >/dev/null 2>&1; then
		echo "  ✗ Failed to create template ${TPROD}"
		# Check if this is a critical error (VM ID already exists)
		if qm status ${TPROD} >/dev/null 2>&1; then
			cleanup_and_exit 1 "VM ${TPROD} already exists. Run template-clean.sh first."
		fi
		return
	fi
	echo "  → Importing disk..."
	if ! IMPORT_OUTPUT=$(qm importdisk ${TPROD} "${TMPISO}" "${STORAGE}" 2>&1); then
		echo "  ✗ Failed to import disk for template ${TPROD}"
		echo "     Try: STORAGE=local-lvm ./template-generate.sh"
		qm destroy ${TPROD} --destroy-unreferenced-disks 1 2>/dev/null
		rm -f "$TMPISO"
		return
	fi

	# Extract the actual disk name from import output
	IMPORTED_DISK=$(echo "$IMPORT_OUTPUT" | grep "unused.*successfully imported disk" | sed "s/.*'\([^']*\)'.*/\1/")
	if [ -z "$IMPORTED_DISK" ]; then
		echo "  ✗ Could not determine imported disk name for template ${TPROD}"
		echo "     Try: STORAGE=local-lvm ./template-generate.sh"
		qm destroy ${TPROD} --destroy-unreferenced-disks 1 2>/dev/null
		rm -f "$TMPISO"
		return
	fi

	echo "  → Configuring template..."
	if ! qm set $TPROD --scsihw virtio-scsi-pci --scsi0 "${IMPORTED_DISK}" >/dev/null 2>&1; then
		echo "  ✗ Could not attach disk to template ${TPROD}"
		qm destroy ${TPROD} --destroy-unreferenced-disks 1 2>/dev/null
		rm -f "$TMPISO"
		return
	fi
	if ! qm set $TPROD --ide3 "${STORAGE}":cloudinit >/dev/null 2>&1; then
		echo "  ✗ Could not create cloud-init disk for template ${TPROD}"
		qm destroy ${TPROD} --destroy-unreferenced-disks 1 2>/dev/null
		rm -f "$TMPISO"
		return
	fi
	qm set $TPROD --boot c --bootdisk scsi0 >/dev/null 2>&1 || {
		echo "  ✗ Error setting boot"
		return
	}
	qm set $TPROD --serial0 socket --vga serial0 >/dev/null 2>&1 || {
		echo "  ✗ Error setting serial"
		return
	}
	qm set $TPROD --agent enabled=1 >/dev/null 2>&1 || {
		echo "  ✗ Error setting agent"
		return
	}
	qm set $TPROD --tag "template,${LCNAME}" >/dev/null 2>&1 || {
		echo "  ✗ Error setting tags"
		return
	}
	qm set $TPROD --ciupgrade 0 >/dev/null 2>&1 || {
		echo "  ✗ Error setting ciupgrade"
		return
	}
	qm set $TPROD --ciuser tgreen >/dev/null 2>&1 || {
		echo "  ✗ Error setting ciuser"
		return
	}
	qm set $TPROD --cipassword "$PW" >/dev/null 2>&1 || {
		echo "  ✗ Error setting password"
		return
	}
	qm set $TPROD --sshkeys ~/.ssh/igor.pub >/dev/null 2>&1 || {
		echo "  ✗ Error setting ssh keys"
		return
	}
	qm set $TPROD --ipconfig0 ip=dhcp >/dev/null 2>&1 || {
		echo "  ✗ Error setting network"
		return
	}

	echo "  → Converting to template..."
	qm template $TPROD >/dev/null 2>&1 || {
		echo "  ✗ Failed to convert VM ${TPROD} to template"
		return
	}

	echo "  ✓ Successfully created template ${TPROD}"
	rm "$TMPISO"

}

# Main execution - sequential processing
echo "Starting template generation..."

# Check prerequisites before starting
check_prerequisites

TEMPLATE_COUNT=0

# Count total templates for progress tracking
TOTAL_TEMPLATES=$(cat $TEMPLATES | grep -Ev "^[[:space:]]*#" | grep -v "^[[:space:]]*$" | grep -cv "Name,Version")
echo "Processing $TOTAL_TEMPLATES templates sequentially"

# Process templates one by one
cat $TEMPLATES | grep -Ev "^[[:space:]]*#" | grep -v "^[[:space:]]*$" | grep -v "Name,Version" | while IFS= read -r LINE; do
	TEMPLATE_COUNT=$((TEMPLATE_COUNT + 1))
	echo ""
	echo "=== [$TEMPLATE_COUNT/$TOTAL_TEMPLATES] Processing: $(echo "$LINE" | awk -F, '{print $1" "$2}') ==="
	process_template "$LINE"
done

echo ""
echo "Template generation completed!"
