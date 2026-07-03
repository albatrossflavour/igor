# @summary Build and configure one infrastructure node by role (charter stage 6).
#
# Replaces the near-identical build_scm / build_cd4pe / build_dashboard plans
# with a single parameterised flow driven by a role table.
# The build sequence is identical for every infrastructure node; only the hiera
# config key, CSR role, and optional install step differ. Adding a new role is
# one entry in the table below plus its hiera config, not another plan.
#
# @param role Which infrastructure role to build.
plan igor::build_infra_node (
  Enum['scm', 'cd4pe', 'dashboard'] $role,
) {
  # Everything that differs between infrastructure nodes lives here.
  $roles = {
    'scm' => {
      'label'        => 'SCM/Comply',
      'config_key'   => 'complyadm::config',
      'csr_role'     => 'role::pe::scm',
      'install_plan' => 'complyadm::install_from_config',
    },
    'cd4pe' => {
      'label'        => 'CD4PE',
      'config_key'   => 'cd4peadm::config',
      'csr_role'     => 'role::pe::cd4pe',
      'install_plan' => 'cd4peadm::install_from_config',
    },
    'dashboard' => {
      'label'        => 'Dashboard',
      'config_key'   => 'dashboard::config',
      'csr_role'     => 'role::pe::dashboard',
      'install_plan' => undef,
    },
  }
  $spec = $roles[$role]

  # Role config and the PE server this node registers against.
  $config = lookup($spec['config_key'], Optional[Hash], first, undef)
  if $config =~ Undef {
    fail_plan("Missing ${spec['config_key']} in hiera for role ${role}")
  }

  $csr_key = regsubst($spec['config_key'], '::config$', '::csr_attributes')
  $csr_attributes = lookup($csr_key, Optional[Hash], first, {
    'datacenter'  => 'lab',
    'environment' => 'production',
  })

  $targets = get_targets($config['resolvable_hostname'])

  $peadm_config = lookup('peadm::config', Optional[Hash], first, undef)
  $puppet_server = $peadm_config['primary_host']

  out::message("Building ${spec['label']} infrastructure")
  out::message("Target: ${targets}")
  out::message("Puppet server: ${puppet_server}")
  out::message('')

  # Skip if Puppet is already installed on the node.
  $check = run_command('test -f /usr/local/bin/puppet', $targets, '_catch_errors' => true)
  if $check.ok {
    out::message("✓ Puppet already installed on ${targets}, skipping")
    return({ 'status' => 'already_installed', 'role' => $role })
  }

  # Classify the node via CSR extension requests before it checks in.
  out::message('Setting up CSR extension requests')
  run_plan('peadm::util::insert_csr_extension_requests',
    'targets'            => $targets,
    'extension_requests' => {
      'pp_datacenter'  => $csr_attributes['datacenter'],
      'pp_role'        => $spec['csr_role'],
      'pp_environment' => $csr_attributes['environment'],
    },
  )

  # Install the agent and let the automatic first run settle.
  out::message('Installing Puppet agent')
  run_task('peadm::agent_install', $targets, 'server' => $puppet_server)
  out::message('Waiting for automatic Puppet run to complete...')
  ctrl::sleep(60)
  run_task('peadm::puppet_runonce', $targets)

  # Role-specific install step, if this role has one.
  if $spec['install_plan'] {
    out::message("Installing ${spec['label']} from config")
    run_plan($spec['install_plan'])
  }

  # Run Puppet twice more to converge.
  out::message('Running Puppet agent to apply configuration')
  run_task('peadm::puppet_runonce', $targets)
  out::message('Running Puppet agent again to ensure convergence')
  run_task('peadm::puppet_runonce', $targets)

  # Dashboard needs its Grafana admin password reset after install.
  if $role == 'dashboard' {
    $grafana_password = lookup('dashboard::grafana_admin_password', String, first, 'grafana')
    out::message('Resetting Grafana admin password')
    run_command("grafana-cli admin reset-admin-password ${grafana_password}", $targets, '_run_as' => 'root')
    out::message("Grafana admin password: ${grafana_password}")
  }

  out::message("${spec['label']} build completed successfully")
  return({ 'status' => 'completed', 'role' => $role })
}
