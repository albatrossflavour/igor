# @summary Stage 0 - build Proxmox VM templates on the hypervisor host
#
# Igor owns operating system template building (see CHARTER.md, stage 0). This
# plan stages the canonical builder onto the Proxmox host over SSH and runs it.
# Missing templates are built; existing ones are skipped unless force_rebuild is
# set. It is safe to run on every deploy: a warm host only pays for templates
# that are actually missing.
#
# Connection and staging details come from the igor::proxmox_host hiera key.
# Add it to data/common.yaml:
#
#   igor::proxmox_host:
#     host:     192.168.5.10     # SSH-reachable address of the PVE host
#     user:     root             # SSH user on the PVE host (NOT the VM ciuser)
#     storage:  ceph             # Proxmox storage for template disks
#     work_dir: /root/templates  # directory on the host to stage into
#
# The template cloud-init password is reused from terraform.tfvars (cipassword),
# so no additional secret is required.
#
# @param force_rebuild Rebuild templates that already exist (default: false)
plan igor::build_templates (
  Boolean $force_rebuild = false,
) {
  $project_root = system::env('PWD')

  $cfg = lookup('igor::proxmox_host', Optional[Hash], first, undef)
  if $cfg =~ Undef {
    fail_plan(@("MISSING_CONFIG"/L))
      Missing igor::proxmox_host in hiera. Add it to data/common.yaml:

        igor::proxmox_host:
          host: 192.168.5.10
          user: root
          storage: ceph
          work_dir: /root/templates

      See CHARTER.md (stage 0) for details.
      | MISSING_CONFIG
  }

  $ssh_host = $cfg['host']
  $ssh_user = $cfg.get('user', 'root')
  $storage  = $cfg.get('storage', 'ceph')
  $work_dir = $cfg.get('work_dir', '/root/templates')

  # The template cipassword is the cloud-init password already captured in
  # terraform.tfvars by ./igor setup. Read it back rather than prompt again.
  $tfvars = "${project_root}/tf/providers/proxmox/terraform.tfvars"
  $cipw_result = run_command(
    "awk -F '\"' '/^[[:space:]]*cipassword/ {print \$2; exit}' ${tfvars}",
    'localhost',
    '_run_as'       => system::env('USER'),
    '_catch_errors' => true,
  )

  unless $cipw_result.ok {
    fail_plan("Could not read ${tfvars}. Run ./igor setup first.")
  }

  $cipassword = $cipw_result.first.value['stdout'].strip
  if $cipassword.empty {
    fail_plan("No cipassword found in ${tfvars}. Run ./igor setup first.")
  }

  # The PVE host is not in the tofu inventory (igor did not create it), so build
  # a Target with an explicit SSH config pointing at the hypervisor.
  $target = Target.new({
    'uri'    => $ssh_host,
    'name'   => 'proxmox-host',
    'config' => {
      'transport' => 'ssh',
      'ssh'       => {
        'user'           => $ssh_user,
        'host-key-check' => false,
      },
    },
  })

  out::message("=== Stage 0: Building Proxmox templates on ${ssh_host} ===")
  out::message("force_rebuild=${force_rebuild}, storage=${storage}, work_dir=${work_dir}")
  out::message('')

  # Stage the builder, the cleaner, and the CSV onto the host.
  run_command("mkdir -p ${work_dir}", $target)
  upload_file("${project_root}/scripts/template-generate.sh", "${work_dir}/template-generate.sh", $target)
  upload_file("${project_root}/scripts/template-clean.sh", "${work_dir}/template-clean.sh", $target)
  upload_file("${project_root}/config/templates.csv", "${work_dir}/templates.csv", $target)

  # Write the password file the script reads via `cat ./config`. tfvars already
  # holds this in plaintext, so this does not lower the existing secret bar;
  # umask 077 keeps it host-local and it is removed after the run.
  run_command("umask 077 && printf '%s' '${cipassword}' > ${work_dir}/config", $target)

  # Run the builder. The script skips existing templates unless FORCE_REBUILD.
  $run = run_command(
    "cd ${work_dir} && FORCE_REBUILD=${force_rebuild} STORAGE=${storage} sh ./template-generate.sh",
    $target,
    '_catch_errors' => true,
  )

  # Always remove the staged password file, success or failure.
  run_command("rm -f ${work_dir}/config", $target, '_catch_errors' => true)

  unless $run.ok {
    fail_plan("Template generation failed: ${run.first.value['stderr']}")
  }

  out::message($run.first.value['stdout'])
  out::message('✓ Stage 0 complete: Proxmox templates ready')

  return({ status => 'completed' })
}
