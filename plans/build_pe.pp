# @summary Install and configure Puppet Enterprise master server
plan igor::build_pe {

  $params = lookup('peadm::config', Hash, first, undef)

  # Lookup CSR attributes separately with defaults
  $csr_attributes = lookup('peadm::csr_attributes', Hash, first, {
    'datacenter' => 'lab',
    'role' => 'role::pe::primary',
    'environment' => 'production'
  })

  $targets = get_targets($params['primary_host'])

  out::message("Building Puppet Enterprise Infrastructure")
  out::message("Target: ${targets}")
  out::message("")

  # Check if Puppet is already installed
  out::message("Checking if Puppet is already installed...")
  $check_puppet = run_command('test -f /usr/local/bin/puppet', $targets, '_catch_errors' => true)

  if $check_puppet.ok {
    out::message("✓ Puppet already installed on ${targets}, skipping installation")
    return({ status => 'already_installed' })
  }

  out::message("Puppet not found, proceeding with installation...")

  # Insert CSR extension requests for PE classification
  out::message("Setting up CSR extension requests...")
  $extension_requests = {
    'pp_datacenter' => $csr_attributes['datacenter'],
    'pp_role' => $csr_attributes['role'],
    'pp_environment' => $csr_attributes['environment']
  }

  run_plan('peadm::util::insert_csr_extension_requests',
    'extension_requests' => $extension_requests,
    'targets' => $targets
  )

  # Actually do the install
  run_plan('peadm::install', $params)

  # Install PE license file as suite-license.lic
  out::message("Installing Puppet Enterprise license (suite-license.lic)...")
  $license_content = lookup('pe_license_content', String, first, undef)

  if $license_content {
    run_task('peadm::mkdir_p_file', $targets,
      'content' => $license_content,
      'path' => '/etc/puppetlabs/suite-license.lic',
      'mode' => '0644',
    )
  } else {
    out::message("Warning: No pe_license_content found in hiera")
  }

  # Deploy code to production environment
  # (the control repo is bootstrapped by the driver's stage_control_repo,
  # which runs before this plan so Code Manager has something to deploy)
  out::message("Deploying code to production environment...")
  run_task('peadm::code_manager', $targets,
    'action' => 'deploy production'
  )

  # Deploy code to development environment
  out::message("Deploying code to development environment...")
  run_task('peadm::code_manager', $targets,
    'action' => 'deploy development'
  )

  # Install eyaml keys for encrypted data
  out::message("Installing eyaml encryption keys...")

  # Read public key content from project directory
  $project_dir = system::env('PWD')
  $public_key_content = file::read("${project_dir}/keys/public_key.pkcs7.pem")
  run_task('peadm::mkdir_p_file', $targets,
    'content' => $public_key_content,
    'path' => '/etc/puppetlabs/secure/keys/public_key.pkcs7.pem',
    'owner' => 'pe-puppet',
    'mode' => '0640',
    'group' => 'pe-puppet',
    'chown_r' => '/etc/puppetlabs/secure'
  )

  # Read private key content
  $private_key_content = file::read("${project_dir}/keys/private_key.pkcs7.pem")
  run_task('peadm::mkdir_p_file', $targets,
    'content' => $private_key_content,
    'path' => '/etc/puppetlabs/secure/keys/private_key.pkcs7.pem',
    'owner' => 'pe-puppet',
    'mode' => '0640',
    'group' => 'pe-puppet',
    'chown_r' => '/etc/puppetlabs/secure'
  )

  # Run Puppet twice to ensure configuration converges
  out::message("Running Puppet agent to apply configuration...")
  run_task('peadm::puppet_runonce', $targets)

  out::message("Running Puppet agent second time to ensure convergence...")
  run_task('peadm::puppet_runonce', $targets)

  # Start puppet service
  out::message("Starting Puppet service...")
  run_task('service', $targets,
    'name' => 'puppet',
    'action' => 'start'
  )

  # CA cert download, console login, and client-tool config are handled by the
  # driver's stage_client_tools, which runs after this plan.

  out::message("Puppet Enterprise build completed successfully")

  return({ status => 'completed' })
}
