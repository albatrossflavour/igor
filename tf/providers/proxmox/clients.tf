# Example of how to consolidate all OS files using for_each
# This would replace all 30+ individual OS template files

locals {
  # Define all OS configurations in one place
  os_configurations = {
    # Alma Linux
    "alma-8-prod" = {
      os_family    = "alma"
      version      = "8"
      environment  = "prod"
      template     = "template-Alma-8"
      vmid_base    = "1110"
      tag_suffix   = "alma"
      enabled      = var.enable_alma
      client_count = var.prod_clients
    }
    "alma-8-dev" = {
      os_family    = "alma"
      version      = "8"
      environment  = "dev"
      template     = "template-Alma-8"
      vmid_base    = "1111"
      tag_suffix   = "alma"
      enabled      = var.enable_alma
      client_count = var.dev_clients
    }
    "alma-9-prod" = {
      os_family    = "alma"
      version      = "9"
      environment  = "prod"
      template     = "template-Alma-9"
      vmid_base    = "1120"
      tag_suffix   = "alma"
      enabled      = var.enable_alma
      client_count = var.prod_clients
    }
    "alma-9-dev" = {
      os_family    = "alma"
      version      = "9"
      environment  = "dev"
      template     = "template-Alma-9"
      vmid_base    = "1121"
      tag_suffix   = "alma"
      enabled      = var.enable_alma
      client_count = var.dev_clients
    }
    "alma-10-prod" = {
      os_family    = "alma"
      version      = "10"
      environment  = "prod"
      template     = "template-Alma-10"
      vmid_base    = "1730"
      tag_suffix   = "alma"
      enabled      = var.enable_alma
      client_count = var.prod_clients
    }
    "alma-10-dev" = {
      os_family    = "alma"
      version      = "10"
      environment  = "dev"
      template     = "template-Alma-10"
      vmid_base    = "1731"
      tag_suffix   = "alma"
      enabled      = var.enable_alma
      client_count = var.dev_clients
    }

    # Ubuntu
    "ubuntu-2004-prod" = {
      os_family    = "ubuntu"
      version      = "2004"
      environment  = "prod"
      template     = "template-Ubuntu-2004"
      vmid_base    = "91230"
      tag_suffix   = "ubuntu"
      enabled      = var.enable_ubuntu
      client_count = var.prod_clients
    }
    "ubuntu-2004-dev" = {
      os_family    = "ubuntu"
      version      = "2004"
      environment  = "dev"
      template     = "template-Ubuntu-2004"
      vmid_base    = "91231"
      tag_suffix   = "ubuntu"
      enabled      = var.enable_ubuntu
      client_count = var.dev_clients
    }
    "ubuntu-2204-prod" = {
      os_family    = "ubuntu"
      version      = "2204"
      environment  = "prod"
      template     = "template-Ubuntu-2204"
      vmid_base    = "91240"
      tag_suffix   = "ubuntu"
      enabled      = var.enable_ubuntu
      client_count = var.prod_clients
    }
    "ubuntu-2204-dev" = {
      os_family    = "ubuntu"
      version      = "2204"
      environment  = "dev"
      template     = "template-Ubuntu-2204"
      vmid_base    = "91241"
      tag_suffix   = "ubuntu"
      enabled      = var.enable_ubuntu
      client_count = var.dev_clients
    }
    "ubuntu-2404-prod" = {
      os_family    = "ubuntu"
      version      = "2404"
      environment  = "prod"
      template     = "template-Ubuntu-2404"
      vmid_base    = "91250"
      tag_suffix   = "ubuntu"
      enabled      = var.enable_ubuntu
      client_count = var.prod_clients
    }
    "ubuntu-2404-dev" = {
      os_family    = "ubuntu"
      version      = "2404"
      environment  = "dev"
      template     = "template-Ubuntu-2404"
      vmid_base    = "91251"
      tag_suffix   = "ubuntu"
      enabled      = var.enable_ubuntu
      client_count = var.dev_clients
    }

    # Rocky Linux
    "rocky-8-prod" = {
      os_family    = "rocky"
      version      = "8"
      environment  = "prod"
      template     = "template-Rocky-8"
      vmid_base    = "1170"
      tag_suffix   = "rocky"
      enabled      = var.enable_rocky
      client_count = var.prod_clients
    }
    "rocky-8-dev" = {
      os_family    = "rocky"
      version      = "8"
      environment  = "dev"
      template     = "template-Rocky-8"
      vmid_base    = "1171"
      tag_suffix   = "rocky"
      enabled      = var.enable_rocky
      client_count = var.dev_clients
    }
    "rocky-9-prod" = {
      os_family    = "rocky"
      version      = "9"
      environment  = "prod"
      template     = "template-Rocky-9"
      vmid_base    = "1180"
      tag_suffix   = "rocky"
      enabled      = var.enable_rocky
      client_count = var.prod_clients
    }
    "rocky-9-dev" = {
      os_family    = "rocky"
      version      = "9"
      environment  = "dev"
      template     = "template-Rocky-9"
      vmid_base    = "1181"
      tag_suffix   = "rocky"
      enabled      = var.enable_rocky
      client_count = var.dev_clients
    }
    "rocky-10-prod" = {
      os_family    = "rocky"
      version      = "10"
      environment  = "prod"
      template     = "template-Rocky-10"
      vmid_base    = "1920"
      tag_suffix   = "rocky"
      enabled      = var.enable_rocky
      client_count = var.prod_clients
    }
    "rocky-10-dev" = {
      os_family    = "rocky"
      version      = "10"
      environment  = "dev"
      template     = "template-Rocky-10"
      vmid_base    = "1921"
      tag_suffix   = "rocky"
      enabled      = var.enable_rocky
      client_count = var.dev_clients
    }

    # Oracle Linux
    "oracle-7-prod" = {
      os_family    = "oracle"
      version      = "7"
      environment  = "prod"
      template     = "template-Oracle-7"
      vmid_base    = "1140"
      tag_suffix   = "oracle"
      enabled      = var.enable_oracle
      client_count = var.prod_clients
    }
    "oracle-7-dev" = {
      os_family    = "oracle"
      version      = "7"
      environment  = "dev"
      template     = "template-Oracle-7"
      vmid_base    = "1141"
      tag_suffix   = "oracle"
      enabled      = var.enable_oracle
      client_count = var.dev_clients
    }
    "oracle-8-prod" = {
      os_family    = "oracle"
      version      = "8"
      environment  = "prod"
      template     = "template-Oracle-8"
      vmid_base    = "1150"
      tag_suffix   = "oracle"
      enabled      = var.enable_oracle
      client_count = var.prod_clients
    }
    "oracle-8-dev" = {
      os_family    = "oracle"
      version      = "8"
      environment  = "dev"
      template     = "template-Oracle-8"
      vmid_base    = "1151"
      tag_suffix   = "oracle"
      enabled      = var.enable_oracle
      client_count = var.dev_clients
    }
    "oracle-9-prod" = {
      os_family    = "oracle"
      version      = "9"
      environment  = "prod"
      template     = "template-Oracle-9"
      vmid_base    = "1130"
      tag_suffix   = "oracle"
      enabled      = var.enable_oracle
      client_count = var.prod_clients
    }
    "oracle-9-dev" = {
      os_family    = "oracle"
      version      = "9"
      environment  = "dev"
      template     = "template-Oracle-9"
      vmid_base    = "1131"
      tag_suffix   = "oracle"
      enabled      = var.enable_oracle
      client_count = var.dev_clients
    }
    "oracle-10-prod" = {
      os_family    = "oracle"
      version      = "10"
      environment  = "prod"
      template     = "template-Oracle-10"
      vmid_base    = "1840"
      tag_suffix   = "oracle"
      enabled      = var.enable_oracle
      client_count = var.prod_clients
    }
    "oracle-10-dev" = {
      os_family    = "oracle"
      version      = "10"
      environment  = "dev"
      template     = "template-Oracle-10"
      vmid_base    = "1841"
      tag_suffix   = "oracle"
      enabled      = var.enable_oracle
      client_count = var.dev_clients
    }

    # Debian
    #   "debian-11-prod" = {
    #     os_family     = "debian"
    #     version       = "11"
    #     environment   = "prod"
    #     template      = "template-Debian-11"
    #     vmid_base     = "5100"
    #     tag_suffix    = "debian"
    #     enabled       = var.enable_debian
    #     client_count  = var.prod_clients
    #   }
    #   "debian-11-dev" = {
    #     os_family     = "debian"
    #     version       = "11"
    #     environment   = "dev"
    #     template      = "template-Debian-11"
    #     vmid_base     = "5110"
    #     tag_suffix    = "debian"
    #     enabled       = var.enable_debian
    #     client_count  = var.dev_clients
    #   }
    "debian-12-prod" = {
      os_family    = "debian"
      version      = "12"
      environment  = "prod"
      template     = "template-Debian-12"
      vmid_base    = "1220"
      tag_suffix   = "debian"
      enabled      = var.enable_debian
      client_count = var.prod_clients
    }
    "debian-12-dev" = {
      os_family    = "debian"
      version      = "12"
      environment  = "dev"
      template     = "template-Debian-12"
      vmid_base    = "1221"
      tag_suffix   = "debian"
      enabled      = var.enable_debian
      client_count = var.dev_clients
    }

    # CentOS 7
    "centos-7-prod" = {
      os_family    = "centos"
      version      = "7"
      environment  = "prod"
      template     = "template-CentOS-7"
      vmid_base    = "1190"
      tag_suffix   = "centos"
      enabled      = var.enable_centos
      client_count = var.prod_clients
    }
    "centos-7-dev" = {
      os_family    = "centos"
      version      = "7"
      environment  = "dev"
      template     = "template-CentOS-7"
      vmid_base    = "1191"
      tag_suffix   = "centos"
      enabled      = var.enable_centos
      client_count = var.dev_clients
    }

    # CentOS Stream
    "centos-stream-prod" = {
      os_family    = "centos"
      version      = "stream"
      environment  = "prod"
      template     = "template-CentOS-Stream"
      vmid_base    = "1160"
      tag_suffix   = "centos"
      enabled      = var.enable_centos
      client_count = var.prod_clients
    }
    "centos-stream-dev" = {
      os_family    = "centos"
      version      = "stream"
      environment  = "dev"
      template     = "template-CentOS-Stream"
      vmid_base    = "1161"
      tag_suffix   = "centos"
      enabled      = var.enable_centos
      client_count = var.dev_clients
    }

    # Red Hat Enterprise Linux
    "rhel-7-prod" = {
      os_family    = "rhel"
      version      = "7"
      environment  = "prod"
      template     = "template-RedHat-7"
      vmid_base    = "1070"
      tag_suffix   = "rhel"
      enabled      = var.enable_redhat
      client_count = var.prod_clients
    }
    "rhel-7-dev" = {
      os_family    = "rhel"
      version      = "7"
      environment  = "dev"
      template     = "template-RedHat-7"
      vmid_base    = "1071"
      tag_suffix   = "rhel"
      enabled      = var.enable_redhat
      client_count = var.dev_clients
    }
    "rhel-8-prod" = {
      os_family    = "rhel"
      version      = "8"
      environment  = "prod"
      template     = "template-RedHat-8"
      vmid_base    = "1080"
      tag_suffix   = "rhel"
      enabled      = var.enable_redhat
      client_count = var.prod_clients
    }
    "rhel-8-dev" = {
      os_family    = "rhel"
      version      = "8"
      environment  = "dev"
      template     = "template-RedHat-8"
      vmid_base    = "1081"
      tag_suffix   = "rhel"
      enabled      = var.enable_redhat
      client_count = var.dev_clients
    }
    "rhel-9-prod" = {
      os_family    = "rhel"
      version      = "9"
      environment  = "prod"
      template     = "template-RedHat-9"
      vmid_base    = "1090"
      tag_suffix   = "rhel"
      enabled      = var.enable_redhat
      client_count = var.prod_clients
    }
    "rhel-9-dev" = {
      os_family    = "rhel"
      version      = "9"
      environment  = "dev"
      template     = "template-RedHat-9"
      vmid_base    = "1091"
      tag_suffix   = "rhel"
      enabled      = var.enable_redhat
      client_count = var.dev_clients
    }
    "rhel-10-prod" = {
      os_family    = "rhel"
      version      = "10"
      environment  = "prod"
      template     = "template-RedHat-10"
      vmid_base    = "1910"
      tag_suffix   = "rhel"
      enabled      = var.enable_redhat
      client_count = var.prod_clients
    }
    "rhel-10-dev" = {
      os_family    = "rhel"
      version      = "10"
      environment  = "dev"
      template     = "template-RedHat-10"
      vmid_base    = "1911"
      tag_suffix   = "rhel"
      enabled      = var.enable_redhat
      client_count = var.dev_clients
    }

    # OpenSUSE
    "opensuse-15-prod" = {
      os_family    = "opensuse"
      version      = "15"
      environment  = "prod"
      template     = "template-OpenSUSE-15.6"
      vmid_base    = "1310"
      tag_suffix   = "opensuse"
      enabled      = var.enable_opensuse
      client_count = var.prod_clients
    }
    "opensuse-15-dev" = {
      os_family    = "opensuse"
      version      = "15"
      environment  = "dev"
      template     = "template-OpenSUSE-15.6"
      vmid_base    = "1311"
      tag_suffix   = "opensuse"
      enabled      = var.enable_opensuse
      client_count = var.dev_clients
    }

    # Amazon Linux
    "amazonlinux-2-prod" = {
      os_family    = "amazonlinux"
      version      = "2"
      environment  = "prod"
      template     = "template-AmazonLinux-2"
      vmid_base    = "1510"
      tag_suffix   = "amazonlinux"
      enabled      = var.enable_amazonlinux
      client_count = var.prod_clients
    }
    "amazonlinux-2-dev" = {
      os_family    = "amazonlinux"
      version      = "2"
      environment  = "dev"
      template     = "template-AmazonLinux-2"
      vmid_base    = "1511"
      tag_suffix   = "amazonlinux"
      enabled      = var.enable_amazonlinux
      client_count = var.dev_clients
    }
  }

  # Filter to only enabled configurations with client_count > 0
  enabled_os_configs = {
    for key, config in local.os_configurations : key => config
    if config.enabled && config.client_count > 0
  }

  # Create flattened list without IPs first
  puppet_clients_base = flatten([
    for config_key, config in local.enabled_os_configs : [
      for i in range(config.client_count) : {
        key          = "${config_key}-${i + 1}"
        config_key   = config_key
        config       = config
        instance_num = i + 1
        vmid         = "${config.vmid_base}${i + 1}"
      }
    ]
  ])

  # Assign sequential IPs starting at .10
  puppet_clients = [
    for idx, client in local.puppet_clients_base : merge(client, {
      ip_address = "192.168.10.${10 + idx}"
    })
  ]

  # Convert to map for for_each
  puppet_clients_map = {
    for client in local.puppet_clients : client.key => client
  }
}

# Single resource definition that replaces all 30+ OS files
resource "proxmox_vm_qemu" "puppet_clients" {
  for_each = local.puppet_clients_map

  target_nodes           = ["ankh", "morpork", "stolat"]
  vmid                   = each.value.vmid
  tags                   = "puppetagents;${each.value.config.environment};${each.value.config.tag_suffix}"
  description            = "${title(each.value.config.os_family)} ${each.value.config.version} ${each.value.config.environment} puppet nodes"
  onboot                 = false
  agent                  = 1
  qemu_os                = "l26"
  agent_timeout          = 600
  clone                  = each.value.config.template
  full_clone             = false
  define_connection_info = false
  os_type                = "cloud-init"
  pool                   = "Puppet"

  cpu {
    type    = "host"
    cores   = var.cores
    sockets = 1
    numa    = true
  }

  memory       = var.memory
  name         = "${each.value.config.os_family}-${each.value.config.version}-puppet-${each.value.config.environment}-${each.value.instance_num}.${var.domain}"
  bootdisk     = "scsi0"
  scsihw       = "virtio-scsi-single"
  ipconfig0    = "ip=${each.value.ip_address}/24,gw=192.168.10.1"
  nameserver   = "192.168.9.2 192.168.9.3"
  searchdomain = var.domain
  ciuser       = var.ciuser
  cipassword   = var.cipassword
  sshkeys      = var.sshkey
  depends_on   = [proxmox_vm_qemu.new-puppet-server[0]]

  network {
    id     = 0
    bridge = "vmbr1"
    model  = "virtio"
    tag    = 6
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage    = var.storage_location
          size       = var.disk_size
          asyncio    = "threads"
          cache      = "writeback"
          discard    = true
          emulatessd = true
          iothread   = true
        }
      }
    }
    ide {
      ide3 {
        cloudinit {
          storage = var.storage_location
        }
      }
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "exit 0"
  }

  lifecycle {
    ignore_changes = [
      clone,
      clone_wait,
      full_clone,
      target_nodes,
      pool
    ]
  }
}

# DNS records for puppet clients

# Optional: Output showing what would be created
output "puppet_clients_to_create" {
  description = "List of puppet clients that will be created"
  value = {
    for key, client in local.puppet_clients_map : key => {
      name     = "${client.config.os_family}-${client.config.version}-puppet-${client.config.environment}-${client.instance_num}"
      vmid     = client.vmid
      template = client.config.template
      enabled  = client.config.enabled
    }
  }
}
