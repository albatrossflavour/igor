#!/opt/puppetlabs/puppet/bin/ruby
# Execute Terraform operations with secrets passed in as environment variables

require 'json'
require 'open3'

def main
  params = JSON.parse(STDIN.read)

  terraform_dir = params['terraform_dir']
  action = params['action']
  args = params['args'] || []
  secrets = params['secrets'] || {}

  # Change to terraform directory
  Dir.chdir(terraform_dir) do

    # Set environment variables from secrets
    env = ENV.to_h
    secrets.each { |key, value| env[key] = value }

    # Build terraform command
    cmd = ['tofu', action] + args

    # Execute terraform command
    stdout, stderr, status = Open3.capture3(env, *cmd)

    if status.success?
      {
        'status' => 'success',
        'stdout' => stdout,
        'stderr' => stderr,
        'exit_code' => status.exitstatus
      }
    else
      {
        'status' => 'error',
        'stdout' => stdout,
        'stderr' => stderr,
        'exit_code' => status.exitstatus,
        'error' => "Terraform #{action} failed with exit code #{status.exitstatus}"
      }
    end
  end

rescue => e
  {
    'status' => 'error',
    'error' => e.message,
    'backtrace' => e.backtrace
  }
end

puts main.to_json
