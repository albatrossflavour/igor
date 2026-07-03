# @summary Interactive first-time setup wizard for Igor
# @param reconfigure Force reconfiguration even if files already exist
# @param provider Infrastructure provider (default: proxmox)
plan igor::setup (
  Boolean $reconfigure = false,
  String $provider = 'proxmox'
) {

  out::message('=== Igor Setup Wizard ===')
  out::message('')
  out::message('This will configure Igor for first-time use.')
  out::message('Press Enter to accept [default] values shown in brackets.')
  out::message('')

  $project_root = system::env('PWD')
  $provider_dir = "tf/providers/${provider}"

  # ---------------------------------------------------------------
  # Phase 1: Check existing configuration
  # ---------------------------------------------------------------
  $tfvars_check = run_command(
    "test -f ${provider_dir}/terraform.tfvars && echo exists || echo missing",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )
  $tfvars_exists = $tfvars_check.first.value['stdout'].strip == 'exists'

  $backend_check = run_command(
    "test -f ${provider_dir}/s3.tfbackend && echo exists || echo missing",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )
  $backend_exists = $backend_check.first.value['stdout'].strip == 'exists'

  $keys_check = run_command(
    "test -f keys/private_key.pkcs7.pem && echo exists || echo missing",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )
  $keys_exist = $keys_check.first.value['stdout'].strip == 'exists'

  if $tfvars_exists and $backend_exists and $keys_exist and !$reconfigure {
    out::message('Configuration files already exist. To reconfigure, run:')
    out::message('  ./igor setup reconfigure=true')
    return({ 'status' => 'already_configured' })
  }

  # ---------------------------------------------------------------
  # Phase 2: eyaml keys
  # ---------------------------------------------------------------
  out::message('--- Encryption Keys ---')

  if $keys_exist and !$reconfigure {
    out::message('  eyaml keys already exist, keeping them.')
    $keys_generated = false
  } else {
    if $keys_exist {
      $keys_confirm = prompt('eyaml keys exist. Regenerate? WARNING: invalidates all encrypted data (yes/no)', 'default' => 'no')
      if $keys_confirm == 'yes' {
        $do_keygen = true
      } else {
        $do_keygen = false
      }
    } else {
      $do_keygen = true
    }

    if $do_keygen {
      out::message('  Generating eyaml keys...')
      $keygen_result = run_command(
        'mkdir -p keys && eyaml createkeys --pkcs7-private-key=keys/private_key.pkcs7.pem --pkcs7-public-key=keys/public_key.pkcs7.pem',
        'localhost',
        '_run_as' => system::env('USER'),
        '_catch_errors' => true
      )

      unless $keygen_result.ok {
        fail_plan("Failed to generate eyaml keys. Is hiera-eyaml installed? (gem install hiera-eyaml)")
      }

      out::message('  eyaml keys generated in keys/')
      $keys_generated = true
    } else {
      $keys_generated = false
    }
  }

  out::message('')

  # ---------------------------------------------------------------
  # Phase 3: Domain & Network
  # ---------------------------------------------------------------
  out::message('--- Domain & Network ---')
  $domain = prompt('Base domain', 'default' => 'albatrossflavour.com')
  out::message('')

  # ---------------------------------------------------------------
  # Phase 4: Proxmox Connection
  # ---------------------------------------------------------------
  out::message('--- Proxmox Connection ---')
  $api_url = prompt('Proxmox API URL (e.g., https://192.168.5.10:8006/api2/json)')
  $proxmox_token_id = prompt('Proxmox API token ID (e.g., terraform@pve!terraform)')
  $proxmox_token_secret = prompt('Proxmox API token secret', 'sensitive' => true)

  # Stage 1 (template building) reaches the PVE host over SSH, which is separate
  # from the API token Terraform uses. Derive the host from the API URL and
  # confirm the SSH user - this is the hypervisor itself, not the VM ciuser.
  $proxmox_ssh_host_default = regsubst($api_url, '^https?://([^:/]+).*$', '\1')
  $proxmox_ssh_host = prompt('Proxmox SSH host', 'default' => $proxmox_ssh_host_default)
  $proxmox_ssh_user = prompt('Proxmox SSH user (root on the PVE host)', 'default' => 'root')
  $proxmox_storage = prompt('Proxmox storage for templates', 'default' => 'ceph')
  out::message('')

  # ---------------------------------------------------------------
  # Phase 5: S3/MinIO Backend
  # ---------------------------------------------------------------
  out::message('--- S3/MinIO State Backend ---')
  $s3_endpoint = prompt('S3/MinIO endpoint URL (e.g., http://s3.example.com)')
  $s3_bucket = prompt('S3 bucket name', 'default' => 'terraform')
  $s3_state_key = prompt('State file key', 'default' => 'igor.tfstate')
  $s3_access_key = prompt('S3 access key')
  $s3_secret_key = prompt('S3 secret key', 'sensitive' => true)
  out::message('')

  # ---------------------------------------------------------------
  # Phase 6: Credentials
  # ---------------------------------------------------------------
  out::message('--- Credentials ---')
  $ciuser = prompt('Cloud-init / SSH username')
  $cipassword = prompt('Cloud-init password', 'sensitive' => true)
  $console_password = prompt('PE console admin password', 'sensitive' => true)
  $pihole_password = prompt('Pihole admin password', 'sensitive' => true)
  out::message('')

  # ---------------------------------------------------------------
  # Phase 7: SSH Keys
  # ---------------------------------------------------------------
  out::message('--- SSH Configuration ---')
  $ssh_private_key_path = prompt('Path to SSH private key', 'default' => '~/.ssh/id_ed25519')
  $ssh_public_key = prompt('SSH public key string (ssh-ed25519 AAAA... user@host)')

  # Expand ~ in the path
  $expanded_key_path_result = run_command(
    "eval echo ${ssh_private_key_path}",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )
  $expanded_key_path = $expanded_key_path_result.first.value['stdout'].strip

  # Verify key exists
  $ssh_verify = run_command(
    "test -f ${expanded_key_path}",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $ssh_verify.ok {
    fail_plan("Cannot find SSH private key at ${expanded_key_path}")
  }

  out::message('')

  # ---------------------------------------------------------------
  # Phase 8: PE Configuration
  # ---------------------------------------------------------------
  out::message('--- Puppet Enterprise ---')
  $pe_version = prompt('PE version', 'default' => '2025.6.0')
  $github_username = prompt('GitHub username (for control repo)')
  $control_repo_name = prompt('Control repo name', 'default' => 'puppet-control-repo')

  $r10k_remote_plain = "git@github.com:${github_username}/${control_repo_name}.git"
  out::message("  r10k_remote will be: ${r10k_remote_plain}")

  $r10k_key_path = prompt('Path to GitHub deploy key (private key for r10k)', 'default' => '~/.ssh/id_ed25519')

  $expanded_r10k_path_result = run_command(
    "eval echo ${r10k_key_path}",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )
  $expanded_r10k_path = $expanded_r10k_path_result.first.value['stdout'].strip

  $r10k_verify = run_command(
    "test -f ${expanded_r10k_path}",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $r10k_verify.ok {
    fail_plan("Cannot find r10k deploy key at ${expanded_r10k_path}")
  }

  # PE license (optional)
  $pe_license_path = prompt('Path to PE license file (leave empty to skip)', 'default' => '')

  # Forge token (optional)
  $forge_token_input = prompt('Puppet Forge API token (leave empty to skip)', 'default' => '')
  out::message('')

  # ---------------------------------------------------------------
  # Phase 9: Components
  # ---------------------------------------------------------------
  out::message('--- Components to Enable ---')
  $enable_pe_input = prompt('Enable Puppet Enterprise? (true/false)', 'default' => 'true')
  $enable_scm_input = prompt('Enable SCM/Comply? (true/false)', 'default' => 'true')
  $enable_cd4pe_input = prompt('Enable CD4PE? (true/false)', 'default' => 'true')
  $enable_dashboard_input = prompt('Enable Dashboard? (true/false)', 'default' => 'true')
  out::message('')

  # ---------------------------------------------------------------
  # Phase 10: Agent Configuration
  # ---------------------------------------------------------------
  out::message('--- Agent Configuration ---')
  $prod_clients_input = prompt('Production clients per OS', 'default' => '1')
  $dev_clients_input = prompt('Development clients per OS', 'default' => '0')
  out::message('')

  # ---------------------------------------------------------------
  # Phase 11: Encrypt sensitive values with eyaml
  # ---------------------------------------------------------------
  out::message('--- Encrypting sensitive values ---')

  $eyaml_opts = '--pkcs7-private-key=keys/private_key.pkcs7.pem --pkcs7-public-key=keys/public_key.pkcs7.pem -o string'

  # Write sensitive values to temp files to avoid shell escaping issues
  # then encrypt from file, then clean up
  $encrypt_cmd = @("ENCRYPT")
    set -e
    cd ${project_root}
    _eyaml="${eyaml_opts}"
    _tmpdir=\$(mktemp -d)
    trap "rm -rf \$_tmpdir" EXIT

    printf '%s' '${console_password.unwrap}' > \$_tmpdir/console_pw
    echo "console_password=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/console_pw)"

    printf '%s' '${r10k_remote_plain}' > \$_tmpdir/r10k_remote
    echo "r10k_remote=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/r10k_remote)"

    cp '${expanded_r10k_path}' \$_tmpdir/r10k_key
    echo "r10k_key=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/r10k_key)"

    echo "grafana_password=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/console_pw)"
    | ENCRYPT

  $encrypt_secrets_result = run_command(
    $encrypt_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $encrypt_secrets_result.ok {
    fail_plan("Failed to encrypt secrets: ${encrypt_secrets_result.first.value['stderr']}")
  }

  $secret_lines = $encrypt_secrets_result.first.value['stdout'].strip.split("\n")
  $secrets = Hash($secret_lines.map |$line| {
    $parts = $line.split('=', 2)
    [$parts[0], $parts[1]]
  })

  # PE license (if provided)
  if $pe_license_path != '' {
    $expanded_license_result = run_command(
      "eval echo ${pe_license_path}",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )
    $expanded_license_path = $expanded_license_result.first.value['stdout'].strip

    $enc_license_result = run_command(
      "cd ${project_root} && eyaml encrypt ${eyaml_opts} -f ${expanded_license_path}",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )
    unless $enc_license_result.ok {
      fail_plan("Failed to encrypt PE license: ${enc_license_result.first.value['stderr']}")
    }
    $pe_license_line = "pe_license_content: ${enc_license_result.first.value['stdout'].strip}"
  } else {
    $pe_license_line = '# pe_license_content: <run igor::setup with pe_license_path to set>'
  }

  # Forge token
  if $forge_token_input != '' {
    $enc_forge_result = run_command(
      "cd ${project_root} && printf '%s' '${forge_token_input}' | eyaml encrypt --stdin ${eyaml_opts}",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )
    $enc_forge_token = $enc_forge_result.first.value['stdout'].strip
  } else {
    $enc_forge_token = 'SKIP'
  }

  # Generate SCM passwords
  out::message('  Generating SCM secrets...')
  $encrypt_scm_cmd = @("ENCRYPT_SCM")
    set -e
    cd ${project_root}
    _eyaml="${eyaml_opts}"
    _tmpdir=\$(mktemp -d)
    trap "rm -rf \$_tmpdir" EXIT
    for name in admin_db comply_db identity_db redis cookie; do
      openssl rand -base64 24 | tr -d '/+=' | head -c 24 > \$_tmpdir/pw
      echo "\${name}=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/pw)"
    done
    openssl rand -hex 16 > \$_tmpdir/pw
    echo "db_encryption_key=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/pw)"
    openssl rand -base64 32 | tr -d '/+=' | head -c 32 > \$_tmpdir/pw
    echo "secret_key=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/pw)"
    for name in identity_account identity_account_console identity_admin_user identity_admin_password identity_admin_cli identity_broker identity_realm_management identity_security_admin_console client_secret; do
      openssl rand -base64 24 | tr -d '/+=' | head -c 24 > \$_tmpdir/pw
      echo "\${name}=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/pw)"
    done
    | ENCRYPT_SCM

  $enc_scm_result = run_command(
    $encrypt_scm_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $enc_scm_result.ok {
    fail_plan("Failed to generate SCM passwords: ${enc_scm_result.first.value['stderr']}")
  }

  $scm_passwords = Hash($enc_scm_result.first.value['stdout'].strip.split("\n").map |$line| {
    $parts = $line.split('=', 2)
    [$parts[0], $parts[1]]
  })

  # Generate CD4PE passwords
  out::message('  Generating CD4PE secrets...')
  $encrypt_cd4pe_cmd = @("ENCRYPT_CD4PE")
    set -e
    cd ${project_root}
    _eyaml="${eyaml_opts}"
    _tmpdir=\$(mktemp -d)
    trap "rm -rf \$_tmpdir" EXIT
    for name in admin_db cd4pe_db query_db root; do
      openssl rand -base64 24 | tr -d '/+=' | head -c 24 > \$_tmpdir/pw
      echo "\${name}=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/pw)"
    done
    openssl rand -base64 32 | tr -d '/+=' | head -c 32 > \$_tmpdir/pw
    echo "secret_key=\$(eyaml encrypt \$_eyaml -f \$_tmpdir/pw)"
    | ENCRYPT_CD4PE

  $enc_cd4pe_result = run_command(
    $encrypt_cd4pe_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $enc_cd4pe_result.ok {
    fail_plan("Failed to generate CD4PE passwords: ${enc_cd4pe_result.first.value['stderr']}")
  }

  $cd4pe_passwords = Hash($enc_cd4pe_result.first.value['stdout'].strip.split("\n").map |$line| {
    $parts = $line.split('=', 2)
    [$parts[0], $parts[1]]
  })

  out::message('  All sensitive values encrypted')
  out::message('')

  # ---------------------------------------------------------------
  # Phase 12: Write terraform.tfvars
  # ---------------------------------------------------------------
  out::message('--- Writing configuration files ---')

  # Write tfvars in two parts: config block, then append SSH key from file
  $write_tfvars_cmd = @("WRITE_TFVARS")
    cat > ${provider_dir}/terraform.tfvars << 'ENDTFVARS'
    puppet_pe        = ${enable_pe_input}
    puppet_cd4pe     = ${enable_cd4pe_input}
    puppet_scm       = ${enable_scm_input}
    puppet_dashboard = ${enable_dashboard_input}

    # OS Distribution Controls
    enable_alma        = true
    enable_centos      = false
    enable_debian      = true
    enable_oracle      = true
    enable_redhat      = false
    enable_rocky       = true
    enable_ubuntu      = true
    enable_opensuse    = false
    enable_amazonlinux = false

    # Client Counts
    prod_clients = ${prod_clients_input}
    dev_clients  = ${dev_clients_input}

    # Proxmox
    api_url              = "${api_url}"
    proxmox_token_id     = "${proxmox_token_id}"
    proxmox_token_secret = "${proxmox_token_secret.unwrap}"

    # Credentials
    ciuser           = "${ciuser}"
    cipassword       = "${cipassword.unwrap}"
    console_password = "${console_password.unwrap}"
    pihole_password  = "${pihole_password.unwrap}"

    # SSH
    sshkey = "${ssh_public_key}"

    # Domain
    domain = "${domain}"
    ENDTFVARS

    printf '\nssh_private_key = <<EOF\n' >> ${provider_dir}/terraform.tfvars
    cat '${expanded_key_path}' >> ${provider_dir}/terraform.tfvars
    printf 'EOF\n' >> ${provider_dir}/terraform.tfvars
    | WRITE_TFVARS

  $write_tfvars_result = run_command(
    $write_tfvars_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $write_tfvars_result.ok {
    fail_plan("Failed to write terraform.tfvars: ${write_tfvars_result.first.value['stderr']}")
  }

  out::message("  ${provider_dir}/terraform.tfvars written")

  # ---------------------------------------------------------------
  # Phase 13: Write s3.tfbackend
  # ---------------------------------------------------------------
  $write_backend_cmd = @("WRITE_BACKEND")
    cat > ${provider_dir}/s3.tfbackend << 'ENDBACKEND'
    bucket                      = "${s3_bucket}"
    key                         = "${s3_state_key}"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true
    endpoint                    = "${s3_endpoint}"
    region                      = "us-east-1"
    secret_key                  = "${s3_secret_key.unwrap}"
    access_key                  = "${s3_access_key}"
    ENDBACKEND
    | WRITE_BACKEND

  $write_backend_result = run_command(
    $write_backend_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $write_backend_result.ok {
    fail_plan("Failed to write s3.tfbackend: ${write_backend_result.first.value['stderr']}")
  }

  out::message("  ${provider_dir}/s3.tfbackend written")

  # ---------------------------------------------------------------
  # Phase 14: Write hiera data files
  # ---------------------------------------------------------------

  # Build forge settings lines for primary yaml
  if $enc_forge_token != 'SKIP' {
    $forge_lines = "    pe_r10k::forge_settings:\n      authorization_token: ${enc_forge_token}\n      baseurl: https://forgeapi.puppet.com\n    puppet_enterprise::master::code_manager::forge_settings:\n      authorization_token: ${enc_forge_token}\n      baseurl: https://forgeapi.puppet.com"
  } else {
    $forge_lines = ''
  }

  # role::pe::primary.yaml
  $write_primary_cmd = @("WRITE_PRIMARY")
    cat > data/roles/role::pe::primary.yaml << 'ENDYAML'
    # PE primary server configuration
    # Generated by igor::setup
    pe_github_username: ${github_username}
    pe_control_repo_name: ${control_repo_name}
    ${pe_license_line}
    peadm::config:
      version: ${pe_version}
      console_password: ${secrets['console_password']}
      primary_host: new-puppet.${domain}
      dns_alt_names:
        - puppet
      code_manager_auto_configure: true
      r10k_known_hosts:
        - name: "github.com"
          type: "ssh-ed25519"
          key: "AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
      r10k_remote: ${secrets['r10k_remote']}
      r10k_private_key_file: ${secrets['r10k_key']}
      pe_conf_data:
    ${forge_lines}
        puppet_enterprise::profile::console::password_minimum_length: 6
        puppet_enterprise::profile::console::uppercase_letters_required: 0
        puppet_enterprise::profile::console::numbers_required: 0
        puppet_enterprise::profile::console::special_characters_required: 0
        puppet_enterprise::profile::master::versioned_deploys: false
    profile::pe::agent_types:
      - pe_repo::platform::el_7_x86_64
      - pe_repo::platform::el_8_x86_64
      - pe_repo::platform::el_9_x86_64
      - pe_repo::platform::ubuntu_2004_amd64
      - pe_repo::platform::ubuntu_2204_amd64
      - pe_repo::platform::ubuntu_2404_amd64
      - pe_repo::platform::debian_11_amd64
      - pe_repo::platform::debian_12_amd64
      - pe_repo::platform::sles_15_x86_64
      - pe_repo::platform::windows_x86_64
    ENDYAML
    | WRITE_PRIMARY

  $write_primary_result = run_command(
    $write_primary_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $write_primary_result.ok {
    fail_plan("Failed to write primary.yaml: ${write_primary_result.first.value['stderr']}")
  }
  out::message('  data/roles/role::pe::primary.yaml written')

  # role::pe::scm.yaml
  $write_scm_cmd = @("WRITE_SCM")
    cat > data/roles/role::pe::scm.yaml << 'ENDYAML'
    complyadm::config:
      targets:
        backend:
          - new-scm.${domain}
        database:
          - new-scm.${domain}
        ui:
          - new-scm.${domain}
      admin_db_password: ${scm_passwords['admin_db']}
      comply_db_password: ${scm_passwords['comply_db']}
      comply_db_username: comply
      db_encryption_key: ${scm_passwords['db_encryption_key']}
      identity_db_password: ${scm_passwords['identity_db']}
      identity_db_username:
      resolvable_hostname: new-scm.${domain}
      runtime: docker
      install_runtime: true
      secret_key: ${scm_passwords['secret_key']}
      identity_account: ${scm_passwords['identity_account']}
      identity_account_console: ${scm_passwords['identity_account_console']}
      identity_admin_user: ${scm_passwords['identity_admin_user']}
      identity_admin_password: ${scm_passwords['identity_admin_password']}
      identity_admin_cli: ${scm_passwords['identity_admin_cli']}
      identity_broker: ${scm_passwords['identity_broker']}
      identity_realm_management: ${scm_passwords['identity_realm_management']}
      identity_security_admin_console: ${scm_passwords['identity_security_admin_console']}
      client_secret: ${scm_passwords['client_secret']}
      cookie_secret: ${scm_passwords['cookie_secret']}
      redis_password: ${scm_passwords['redis_password']}
      user_assessor_version: latest
    complyadm::csr_attributes:
      datacenter: lab
      role: role::pe::scm
      environment: production
    ENDYAML
    | WRITE_SCM

  $write_scm_result = run_command(
    $write_scm_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $write_scm_result.ok {
    fail_plan("Failed to write scm.yaml: ${write_scm_result.first.value['stderr']}")
  }
  out::message('  data/roles/role::pe::scm.yaml written')

  # role::pe::cd4pe.yaml
  $write_cd4pe_cmd = @("WRITE_CD4PE")
    cat > data/roles/role::pe::cd4pe.yaml << 'ENDYAML'
    cd4peadm::config:
      targets:
        backend:
          - new-cd4pe.${domain}
        database:
          - new-cd4pe.${domain}
        ui:
          - new-cd4pe.${domain}
      admin_db_password: ${cd4pe_passwords['admin_db']}
      cd4pe_db_password: ${cd4pe_passwords['cd4pe_db']}
      cd4pe_db_username: cd4pe
      query_db_password: ${cd4pe_passwords['query_db']}
      query_db_username: query
      resolvable_hostname: new-cd4pe.${domain}
      root_password: ${cd4pe_passwords['root']}
      root_username: admin
      runtime: docker
      secret_key: ${cd4pe_passwords['secret_key']}
    cd4peadm::csr_attributes:
      datacenter: lab
      role: role::pe::cd4pe
      environment: production
    ENDYAML
    | WRITE_CD4PE

  $write_cd4pe_result = run_command(
    $write_cd4pe_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $write_cd4pe_result.ok {
    fail_plan("Failed to write cd4pe.yaml: ${write_cd4pe_result.first.value['stderr']}")
  }
  out::message('  data/roles/role::pe::cd4pe.yaml written')

  # role::pe::dashboard.yaml
  $write_dashboard_cmd = @("WRITE_DASHBOARD")
    cat > data/roles/role::pe::dashboard.yaml << 'ENDYAML'
    dashboard::config:
      resolvable_hostname: new-dashboard.${domain}
    dashboard::csr_attributes:
      datacenter: lab
      role: role::pe::dashboard
      environment: production
    dashboard::grafana_admin_password: ${secrets['grafana_password']}
    ENDYAML
    | WRITE_DASHBOARD

  $write_dashboard_result = run_command(
    $write_dashboard_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $write_dashboard_result.ok {
    fail_plan("Failed to write dashboard.yaml: ${write_dashboard_result.first.value['stderr']}")
  }
  out::message('  data/roles/role::pe::dashboard.yaml written')

  # common.yaml
  $write_common_cmd = @(WRITE_COMMON)
    cat > data/common.yaml << 'ENDYAML'
    # Common configuration for all nodes
    # Role-specific configuration is in data/roles/

    # Proxmox host for stage 1 template building (SSH, not the API token)
    igor::proxmox_host:
      host: ${proxmox_ssh_host}
      user: ${proxmox_ssh_user}
      storage: ${proxmox_storage}
      work_dir: /root/templates
    ENDYAML
    | WRITE_COMMON

  $write_common_result = run_command(
    $write_common_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )
  out::message('  data/common.yaml written')

  # ---------------------------------------------------------------
  # Phase 15: Update inventory.yaml
  # ---------------------------------------------------------------
  $write_inventory_cmd = @("WRITE_INVENTORY")
    cat > inventory.yaml << 'ENDYAML'
    version: 2
    config:
      transport: ssh
      ssh:
        private-key: ${ssh_private_key_path}
        user: ${ciuser}
        run-as: root
        host-key-check: false
        tmpdir: /var/tmp
    groups:
      - name: puppet-infrastructure
        targets:
          _plugin: task
          task: igor::tofu_inventory
          parameters:
            provider: ${provider}
            tag_filter: puppetinfra
      - name: puppet-enterprise-nodes
        targets:
          _plugin: task
          task: igor::tofu_inventory
          parameters:
            provider: ${provider}
            tag_filter: puppet
      - name: scm-nodes
        targets:
          _plugin: task
          task: igor::tofu_inventory
          parameters:
            provider: ${provider}
            tag_filter: scm
      - name: cd4pe-nodes
        targets:
          _plugin: task
          task: igor::tofu_inventory
          parameters:
            provider: ${provider}
            tag_filter: cd4pe
      - name: dashboard-nodes
        targets:
          _plugin: task
          task: igor::tofu_inventory
          parameters:
            provider: ${provider}
            tag_filter: dashboard
      - name: puppet-agents
        targets:
          _plugin: task
          task: igor::tofu_inventory
          parameters:
            provider: ${provider}
            tag_filter: puppetagents
    ENDYAML
    | WRITE_INVENTORY

  $write_inventory_result = run_command(
    $write_inventory_cmd,
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )
  out::message('  inventory.yaml written')
  out::message('')

  # ---------------------------------------------------------------
  # Phase 16: Install Bolt modules
  # ---------------------------------------------------------------
  out::message('--- Installing Bolt modules ---')

  $module_result = run_command(
    'bolt module install',
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $module_result.ok {
    out::message('  Bolt modules installed')
  } else {
    out::message("  WARNING: bolt module install failed")
    out::message('  Run manually: bolt module install')
  }

  out::message('')

  # ---------------------------------------------------------------
  # Phase 17: Initialize tofu
  # ---------------------------------------------------------------
  out::message('--- Initializing OpenTofu ---')

  $tofu_init_result = run_command(
    "cd ${provider_dir} && tofu init -backend-config=./s3.tfbackend",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $tofu_init_result.ok {
    out::message('  OpenTofu initialized')
  } else {
    out::message('  WARNING: tofu init failed. Check s3.tfbackend credentials.')
    out::message("  Run manually: cd ${provider_dir} && tofu init -backend-config=./s3.tfbackend")
  }

  out::message('')
  out::message('=== Igor Setup Complete ===')
  out::message('')
  out::message('Next steps:')
  out::message('  bolt plan run igor::preflight')
  out::message('  ./igor deploy')
  out::message('')

  return({
    'status' => 'completed',
    'domain' => $domain,
    'provider' => $provider,
    'keys_generated' => $keys_generated
  })
}
