#!/usr/bin/env ruby
# frozen_string_literal: true

# igor-setup.rb - interactive first-time setup wizard for Igor.
#
# This is the Ruby replacement for the old `plans/setup.pp` Bolt plan. It walks
# through the same phases (eyaml keys, prompts, eyaml encryption, config file
# writing, tofu init) but folds in the op:// secrets model:
#
#   * TF secrets (proxmox token secret, cipassword, console password, pihole
#     password) live in 1Password, not in terraform.tfvars.
#   * S3 backend credentials live in 1Password, not in s3.tfbackend.
#   * Puppet/PE secrets are still eyaml-encrypted into the role yamls, exactly
#     as before.
#
# The 1Password items are created in the `proxtoboltfu` vault so that
# `op run --env-file=secrets.env -- tofu ...` can resolve them at apply time.
#
# Run via `./igor setup` (which execs this script). Pass `reconfigure=true` to
# force reconfiguration even when config already exists.

require 'io/console'
require 'open3'
require 'tempfile'
require 'fileutils'
require 'shellwords'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

VAULT = 'proxtoboltfu'

EYAML_KEYS = [
  '--pkcs7-private-key=keys/private_key.pkcs7.pem',
  '--pkcs7-public-key=keys/public_key.pkcs7.pem'
].freeze

# Password generation pipelines, kept identical to the old plan so the shape of
# the generated secrets does not change.
GEN_PW24    = "openssl rand -base64 24 | tr -d '/+=' | head -c 24"
GEN_HEX16   = 'openssl rand -hex 16'
GEN_SECRET32 = "openssl rand -base64 32 | tr -d '/+=' | head -c 32"

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def say(msg = '')
  puts msg
end

def die(msg)
  warn "ERROR: #{msg}"
  exit 1
end

# Run a command, returning [stdout, stderr, ok?].
def run(*cmd)
  out, err, status = Open3.capture3(*cmd)
  [out, err, status.success?]
end

# Run a command feeding data on stdin, returning [stdout, stderr, ok?].
def run_stdin(input, *cmd)
  out, err, status = Open3.capture3(*cmd, stdin_data: input)
  [out, err, status.success?]
end

# Prompt with an optional default shown in brackets. Returns the default when
# the user just presses Enter. A default of '' still shows `[]` and allows an
# empty answer (used for the optional PE licence / forge token).
def prompt(message, default = nil)
  if default.nil?
    print "#{message}: "
  else
    print "#{message} [#{default}]: "
  end
  input = $stdin.gets
  input = input.nil? ? '' : input.chomp
  if input.empty? && !default.nil?
    default
  else
    input
  end
end

# Prompt for a secret without echoing keystrokes.
def prompt_secret(message)
  print "#{message}: "
  value = $stdin.noecho(&:gets)
  puts ''
  value.nil? ? '' : value.chomp
end

def file_exists?(path)
  File.file?(path)
end

# ---------------------------------------------------------------------------
# eyaml helpers
# ---------------------------------------------------------------------------

# Encrypt the contents of a file with eyaml, returning the encrypted string.
def eyaml_encrypt_file(path)
  out, err, ok = run('eyaml', 'encrypt', *EYAML_KEYS, '-o', 'string', '-f', path)
  die("eyaml encrypt failed for #{path}: #{err}") unless ok
  out.strip
end

# Encrypt a literal value with eyaml. The value is written to a temp file with
# no trailing newline (matching the old plan's `printf '%s'`) then encrypted.
def eyaml_encrypt_value(value)
  Tempfile.create('igor-secret') do |f|
    f.write(value)
    f.flush
    return eyaml_encrypt_file(f.path)
  end
end

# Encrypt a value via eyaml --stdin (used for the forge token).
def eyaml_encrypt_stdin(value)
  out, err, ok = run_stdin(value, 'eyaml', 'encrypt', '--stdin', *EYAML_KEYS, '-o', 'string')
  die("eyaml encrypt (stdin) failed: #{err}") unless ok
  out.strip
end

# Generate a secret using the given shell pipeline, then eyaml-encrypt it.
# The pipeline output is redirected to a temp file exactly as the old plan did,
# so the newline behaviour (e.g. openssl rand -hex 16 keeps its trailing
# newline) is preserved.
def eyaml_encrypt_generated(pipeline)
  Tempfile.create('igor-gen') do |f|
    f.close
    ok = system('/bin/sh', '-c', "#{pipeline} > #{Shellwords.escape(f.path)}")
    die("secret generation failed: #{pipeline}") unless ok
    return eyaml_encrypt_file(f.path)
  end
end

# ---------------------------------------------------------------------------
# 1Password helpers
#
# NOTE: these write to the user's 1Password account (my.1password.com), into
# the `proxtoboltfu` vault. Field labels must match the op:// references in
# tf/providers/proxmox/secrets.env exactly, otherwise `op run` cannot resolve
# them at tofu apply time.
# ---------------------------------------------------------------------------

def op_item_exists?(title)
  system('op', 'item', 'get', title, '--vault', VAULT,
         out: File::NULL, err: File::NULL)
end

# Ensure a 1Password item exists with the given fields. Creates the item if it
# is missing, or edits it to set the fields if it already exists.
#
# Field assignments are passed as separate argv tokens (no shell), so values
# containing shell metacharacters are safe. They are briefly visible in the
# process list while `op` runs - acceptable for a one-off interactive setup.
def ensure_op_item(title, fields)
  assignments = fields.map { |k, v| "#{k}=#{v}" }
  if op_item_exists?(title)
    out, err, ok = run('op', 'item', 'edit', title, '--vault', VAULT, *assignments)
    die("failed to update 1Password item #{title}: #{err}#{out}") unless ok
    say "  updated op://#{VAULT}/#{title}"
  else
    out, err, ok = run('op', 'item', 'create', '--category=password',
                       "--vault=#{VAULT}", "--title=#{title}", *assignments)
    die("failed to create 1Password item #{title}: #{err}#{out}") unless ok
    say "  created op://#{VAULT}/#{title}"
  end
end

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

reconfigure = false
provider = 'proxmox'

ARGV.each do |arg|
  case arg
  when /\Areconfigure=(.+)\z/
    reconfigure = (Regexp.last_match(1) == 'true')
  when /\Aprovider=(.+)\z/
    provider = Regexp.last_match(1)
  else
    die("Unknown argument: #{arg}")
  end
end

project_root = Dir.pwd
provider_dir = "tf/providers/#{provider}"
tfvars_path  = "#{provider_dir}/terraform.tfvars"
backend_path = "#{provider_dir}/s3.tfbackend"
secrets_env  = "#{provider_dir}/secrets.env"

# ---------------------------------------------------------------------------
# Intro
# ---------------------------------------------------------------------------

say '=== Igor Setup Wizard ==='
say ''
say 'This will configure Igor for first-time use.'
say 'Press Enter to accept [default] values shown in brackets.'
say ''

# ---------------------------------------------------------------------------
# Phase 1: Check existing configuration
# ---------------------------------------------------------------------------

tfvars_exists  = file_exists?(tfvars_path)
backend_exists = file_exists?(backend_path)
keys_exist     = file_exists?('keys/private_key.pkcs7.pem')

if tfvars_exists && backend_exists && keys_exist && !reconfigure
  say 'Configuration files already exist. To reconfigure, run:'
  say '  ./igor setup reconfigure=true'
  exit 0
end

# ---------------------------------------------------------------------------
# Phase 2: eyaml keys
# ---------------------------------------------------------------------------

say '--- Encryption Keys ---'

keys_generated = false
if keys_exist && !reconfigure
  say '  eyaml keys already exist, keeping them.'
else
  do_keygen = if keys_exist
                answer = prompt('eyaml keys exist. Regenerate? WARNING: invalidates all encrypted data (yes/no)', 'no')
                answer == 'yes'
              else
                true
              end

  if do_keygen
    say '  Generating eyaml keys...'
    FileUtils.mkdir_p('keys')
    _out, _err, ok = run('eyaml', 'createkeys',
                         '--pkcs7-private-key=keys/private_key.pkcs7.pem',
                         '--pkcs7-public-key=keys/public_key.pkcs7.pem')
    die('Failed to generate eyaml keys. Is hiera-eyaml installed? (gem install hiera-eyaml)') unless ok
    say '  eyaml keys generated in keys/'
    keys_generated = true
  end
end

say ''

# ---------------------------------------------------------------------------
# Phase 3: Domain & Network
# ---------------------------------------------------------------------------

say '--- Domain & Network ---'
domain = prompt('Base domain', 'albatrossflavour.com')
say ''

# ---------------------------------------------------------------------------
# Phase 4: Proxmox Connection
# ---------------------------------------------------------------------------

say '--- Proxmox Connection ---'
api_url = prompt('Proxmox API URL (e.g., https://192.168.5.10:8006/api2/json)')
proxmox_token_id = prompt('Proxmox API token ID (e.g., terraform@pve!terraform)')
proxmox_token_secret = prompt_secret('Proxmox API token secret')
say ''

# ---------------------------------------------------------------------------
# Phase 5: S3/MinIO Backend
# ---------------------------------------------------------------------------

say '--- S3/MinIO State Backend ---'
s3_endpoint = prompt('S3/MinIO endpoint URL (e.g., http://s3.example.com)')
s3_bucket = prompt('S3 bucket name', 'terraform')
s3_state_key = prompt('State file key', 'igor.tfstate')
s3_access_key = prompt('S3 access key')
s3_secret_key = prompt_secret('S3 secret key')
say ''

# ---------------------------------------------------------------------------
# Phase 6: Credentials
# ---------------------------------------------------------------------------

say '--- Credentials ---'
ciuser = prompt('Cloud-init / SSH username')
cipassword = prompt_secret('Cloud-init password')
console_password = prompt_secret('PE console admin password')
pihole_password = prompt_secret('Pihole admin password')
say ''

# ---------------------------------------------------------------------------
# Phase 7: SSH Keys
# ---------------------------------------------------------------------------

say '--- SSH Configuration ---'
ssh_private_key_path = prompt('Path to SSH private key', '~/.ssh/id_ed25519')
ssh_public_key = prompt('SSH public key string (ssh-ed25519 AAAA... user@host)')

expanded_key_path = File.expand_path(ssh_private_key_path)
die("Cannot find SSH private key at #{expanded_key_path}") unless file_exists?(expanded_key_path)

say ''

# ---------------------------------------------------------------------------
# Phase 8: PE Configuration
# ---------------------------------------------------------------------------

say '--- Puppet Enterprise ---'
pe_version = prompt('PE version', '2025.6.0')
github_username = prompt('GitHub username (for control repo)')
control_repo_name = prompt('Control repo name', 'puppet-control-repo')

r10k_remote_plain = "git@github.com:#{github_username}/#{control_repo_name}.git"
say "  r10k_remote will be: #{r10k_remote_plain}"

r10k_key_path = prompt('Path to GitHub deploy key (private key for r10k)', '~/.ssh/id_ed25519')
expanded_r10k_path = File.expand_path(r10k_key_path)
die("Cannot find r10k deploy key at #{expanded_r10k_path}") unless file_exists?(expanded_r10k_path)

pe_license_path = prompt('Path to PE license file (leave empty to skip)', '')
forge_token_input = prompt('Puppet Forge API token (leave empty to skip)', '')
say ''

# ---------------------------------------------------------------------------
# Phase 9: Components
# ---------------------------------------------------------------------------

say '--- Components to Enable ---'
enable_pe_input = prompt('Enable Puppet Enterprise? (true/false)', 'true')
enable_scm_input = prompt('Enable SCM/Comply? (true/false)', 'true')
enable_cd4pe_input = prompt('Enable CD4PE? (true/false)', 'true')
enable_dashboard_input = prompt('Enable Dashboard? (true/false)', 'true')
say ''

# ---------------------------------------------------------------------------
# Phase 10: Agent Configuration
# ---------------------------------------------------------------------------

say '--- Agent Configuration ---'
prod_clients_input = prompt('Production clients per OS', '1')
dev_clients_input = prompt('Development clients per OS', '0')
say ''

# ---------------------------------------------------------------------------
# Phase 11: Encrypt sensitive values with eyaml
# ---------------------------------------------------------------------------

say '--- Encrypting sensitive values ---'

enc_console_password = eyaml_encrypt_value(console_password)
enc_r10k_remote      = eyaml_encrypt_value(r10k_remote_plain)
enc_r10k_key         = eyaml_encrypt_file(expanded_r10k_path)
# grafana password is the same value as the console password (encrypted afresh).
enc_grafana_password = eyaml_encrypt_value(console_password)

# PE licence (optional)
pe_license_line =
  if pe_license_path != ''
    expanded_license_path = File.expand_path(pe_license_path)
    enc_license = eyaml_encrypt_file(expanded_license_path)
    "pe_license_content: #{enc_license}"
  else
    '# pe_license_content: <run igor::setup with pe_license_path to set>'
  end

# Forge token (optional)
enc_forge_token =
  if forge_token_input != ''
    eyaml_encrypt_stdin(forge_token_input)
  else
    'SKIP'
  end

# Generate SCM passwords. Field names match the scm.yaml template below.
# (The old plans/setup.pp generated `redis`/`cookie` but the template referenced
# `redis_password`/`cookie_secret`, so those two came out empty; fixed here.)
say '  Generating SCM secrets...'
scm = {}
%w[admin_db comply_db identity_db redis_password cookie_secret].each do |name|
  scm[name] = eyaml_encrypt_generated(GEN_PW24)
end
scm['db_encryption_key'] = eyaml_encrypt_generated(GEN_HEX16)
scm['secret_key'] = eyaml_encrypt_generated(GEN_SECRET32)
%w[
  identity_account identity_account_console identity_admin_user
  identity_admin_password identity_admin_cli identity_broker
  identity_realm_management identity_security_admin_console client_secret
].each do |name|
  scm[name] = eyaml_encrypt_generated(GEN_PW24)
end

# Generate CD4PE passwords.
say '  Generating CD4PE secrets...'
cd4pe = {}
%w[admin_db cd4pe_db query_db root].each do |name|
  cd4pe[name] = eyaml_encrypt_generated(GEN_PW24)
end
cd4pe['secret_key'] = eyaml_encrypt_generated(GEN_SECRET32)

say '  All sensitive values encrypted'
say ''

# ---------------------------------------------------------------------------
# Phase 11b: 1Password items (TF + S3 secrets)
#
# These must exist before `tofu init` runs, since the S3 backend reads AWS
# credentials from 1Password via `op run`.
# ---------------------------------------------------------------------------

say '--- Storing secrets in 1Password ---'
ensure_op_item('proxmox-credentials',
               'token_secret' => proxmox_token_secret,
               'cipassword' => cipassword)
# console_password is used by BOTH terraform (here) and Puppet (eyaml, below).
ensure_op_item('pe-credentials', 'console_password' => console_password)
ensure_op_item('pihole-credentials', 'password' => pihole_password)
ensure_op_item('aws-s3-backend',
               'access_key_id' => s3_access_key,
               'secret_access_key' => s3_secret_key)
say ''

# ---------------------------------------------------------------------------
# Phase 12: Write terraform.tfvars (no plaintext secrets)
# ---------------------------------------------------------------------------

say '--- Writing configuration files ---'

FileUtils.mkdir_p(provider_dir)
FileUtils.mkdir_p('data/roles')

tfvars = <<~TFVARS
  puppet_pe        = #{enable_pe_input}
  puppet_cd4pe     = #{enable_cd4pe_input}
  puppet_scm       = #{enable_scm_input}
  puppet_dashboard = #{enable_dashboard_input}

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
  prod_clients = #{prod_clients_input}
  dev_clients  = #{dev_clients_input}

  # Proxmox
  api_url              = "#{api_url}"
  proxmox_token_id     = "#{proxmox_token_id}"

  # Credentials
  ciuser           = "#{ciuser}"

  # SSH
  sshkey = "#{ssh_public_key}"

  # Domain
  domain = "#{domain}"
TFVARS

# Append the SSH private key from file as a heredoc, matching the old plan.
tfvars += "\nssh_private_key = <<EOF\n"
tfvars += File.read(expanded_key_path)
tfvars += "EOF\n"

File.write(tfvars_path, tfvars)
say "  #{tfvars_path} written"

# ---------------------------------------------------------------------------
# Phase 13: Write s3.tfbackend (no access_key / secret_key)
# ---------------------------------------------------------------------------

backend = <<~BACKEND
  bucket                      = "#{s3_bucket}"
  key                         = "#{s3_state_key}"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  use_path_style              = true
  endpoint                    = "#{s3_endpoint}"
  region                      = "us-east-1"
BACKEND

File.write(backend_path, backend)
say "  #{backend_path} written"

# ---------------------------------------------------------------------------
# Phase 14: Write hiera data files
# ---------------------------------------------------------------------------

# Forge settings block for the primary yaml (indented to sit under pe_conf_data).
forge_block =
  if enc_forge_token != 'SKIP'
    "    pe_r10k::forge_settings:\n" \
    "      authorization_token: #{enc_forge_token}\n" \
    "      baseurl: https://forgeapi.puppet.com\n" \
    "    puppet_enterprise::master::code_manager::forge_settings:\n" \
    "      authorization_token: #{enc_forge_token}\n" \
    '      baseurl: https://forgeapi.puppet.com'
  else
    ''
  end

primary = <<~PRIMARY
  # PE primary server configuration
  # Generated by igor::setup
  pe_github_username: #{github_username}
  pe_control_repo_name: #{control_repo_name}
  #{pe_license_line}
  peadm::config:
    version: #{pe_version}
    console_password: #{enc_console_password}
    primary_host: new-puppet.#{domain}
    dns_alt_names:
      - puppet
    code_manager_auto_configure: true
    r10k_known_hosts:
      - name: "github.com"
        type: "ssh-ed25519"
        key: "AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
    r10k_remote: #{enc_r10k_remote}
    r10k_private_key_file: #{enc_r10k_key}
    pe_conf_data:
  #{forge_block}
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
PRIMARY

File.write('data/roles/role::pe::primary.yaml', primary)
say '  data/roles/role::pe::primary.yaml written'

scm_yaml = <<~SCM
  complyadm::config:
    targets:
      backend:
        - new-scm.#{domain}
      database:
        - new-scm.#{domain}
      ui:
        - new-scm.#{domain}
    admin_db_password: #{scm['admin_db']}
    comply_db_password: #{scm['comply_db']}
    comply_db_username: comply
    db_encryption_key: #{scm['db_encryption_key']}
    identity_db_password: #{scm['identity_db']}
    identity_db_username:
    resolvable_hostname: new-scm.#{domain}
    runtime: docker
    install_runtime: true
    secret_key: #{scm['secret_key']}
    identity_account: #{scm['identity_account']}
    identity_account_console: #{scm['identity_account_console']}
    identity_admin_user: #{scm['identity_admin_user']}
    identity_admin_password: #{scm['identity_admin_password']}
    identity_admin_cli: #{scm['identity_admin_cli']}
    identity_broker: #{scm['identity_broker']}
    identity_realm_management: #{scm['identity_realm_management']}
    identity_security_admin_console: #{scm['identity_security_admin_console']}
    client_secret: #{scm['client_secret']}
    cookie_secret: #{scm['cookie_secret']}
    redis_password: #{scm['redis_password']}
    user_assessor_version: latest
  complyadm::csr_attributes:
    datacenter: lab
    role: role::pe::scm
    environment: production
SCM

File.write('data/roles/role::pe::scm.yaml', scm_yaml)
say '  data/roles/role::pe::scm.yaml written'

cd4pe_yaml = <<~CD4PE
  cd4peadm::config:
    targets:
      backend:
        - new-cd4pe.#{domain}
      database:
        - new-cd4pe.#{domain}
      ui:
        - new-cd4pe.#{domain}
    admin_db_password: #{cd4pe['admin_db']}
    cd4pe_db_password: #{cd4pe['cd4pe_db']}
    cd4pe_db_username: cd4pe
    query_db_password: #{cd4pe['query_db']}
    query_db_username: query
    resolvable_hostname: new-cd4pe.#{domain}
    root_password: #{cd4pe['root']}
    root_username: admin
    runtime: docker
    secret_key: #{cd4pe['secret_key']}
  cd4peadm::csr_attributes:
    datacenter: lab
    role: role::pe::cd4pe
    environment: production
CD4PE

File.write('data/roles/role::pe::cd4pe.yaml', cd4pe_yaml)
say '  data/roles/role::pe::cd4pe.yaml written'

dashboard_yaml = <<~DASHBOARD
  dashboard::config:
    resolvable_hostname: new-dashboard.#{domain}
  dashboard::csr_attributes:
    datacenter: lab
    role: role::pe::dashboard
    environment: production
  dashboard::grafana_admin_password: #{enc_grafana_password}
DASHBOARD

File.write('data/roles/role::pe::dashboard.yaml', dashboard_yaml)
say '  data/roles/role::pe::dashboard.yaml written'

# common.yaml - just the header now. The driver derives the Proxmox host from
# api_url and defaults user=root, storage=ceph, so igor::proxmox_host is gone.
common = <<~COMMON
  # Common configuration for all nodes
  # Role-specific configuration is in data/roles/
COMMON

File.write('data/common.yaml', common)
say '  data/common.yaml written'

# ---------------------------------------------------------------------------
# Phase 15: Update inventory.yaml
# ---------------------------------------------------------------------------

inventory = <<~INVENTORY
  version: 2
  config:
    transport: ssh
    ssh:
      private-key: #{ssh_private_key_path}
      user: #{ciuser}
      run-as: root
      host-key-check: false
      tmpdir: /var/tmp
  groups:
    - name: puppet-infrastructure
      targets:
        _plugin: task
        task: igor::tofu_inventory
        parameters:
          provider: #{provider}
          tag_filter: puppetinfra
    - name: puppet-enterprise-nodes
      targets:
        _plugin: task
        task: igor::tofu_inventory
        parameters:
          provider: #{provider}
          tag_filter: puppet
    - name: scm-nodes
      targets:
        _plugin: task
        task: igor::tofu_inventory
        parameters:
          provider: #{provider}
          tag_filter: scm
    - name: cd4pe-nodes
      targets:
        _plugin: task
        task: igor::tofu_inventory
        parameters:
          provider: #{provider}
          tag_filter: cd4pe
    - name: dashboard-nodes
      targets:
        _plugin: task
        task: igor::tofu_inventory
        parameters:
          provider: #{provider}
          tag_filter: dashboard
    - name: puppet-agents
      targets:
        _plugin: task
        task: igor::tofu_inventory
        parameters:
          provider: #{provider}
          tag_filter: puppetagents
INVENTORY

File.write('inventory.yaml', inventory)
say '  inventory.yaml written'
say ''

# ---------------------------------------------------------------------------
# Phase 16: Install Bolt modules
# ---------------------------------------------------------------------------

say '--- Installing Bolt modules ---'
_out, _err, ok = run('bolt', 'module', 'install')
if ok
  say '  Bolt modules installed'
else
  say '  WARNING: bolt module install failed'
  say '  Run manually: bolt module install'
end
say ''

# ---------------------------------------------------------------------------
# Phase 17: Initialize tofu (S3 creds injected from 1Password via op run)
# ---------------------------------------------------------------------------

say '--- Initializing OpenTofu ---'
tofu_cmd = "cd #{Shellwords.escape(provider_dir)} && tofu init -backend-config=./s3.tfbackend"
ok = system('op', 'run', "--env-file=#{secrets_env}", '--',
            'sh', '-c', tofu_cmd)
if ok
  say '  OpenTofu initialized'
else
  say '  WARNING: tofu init failed. Check the aws-s3-backend 1Password item and s3.tfbackend.'
  say "  Run manually: op run --env-file=#{secrets_env} -- sh -c '#{tofu_cmd}'"
end

say ''
say '=== Igor Setup Complete ==='
say ''
say 'Next steps:'
say '  ./igor preflight'
say '  ./igor deploy'
say ''

# Keep project_root referenced (parity with the old plan's PWD usage).
_ = project_root
