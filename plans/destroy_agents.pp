# @summary Destroy puppet agent clients using OpenTofu
# @param confirm Safety confirmation (must be true to proceed with destroy)
# @param provider Infrastructure provider (default: proxmox)
plan igor::destroy_agents (
  Boolean $confirm = false,
  String $provider = 'proxmox'
) {

  out::message('=== Puppet Agent Clients Destroy Plan ===')
  out::message('')

  # Get current agent inventory to show what will be destroyed
  $agent_inventory = run_task('igor::tofu_inventory', 'localhost',
    'provider' => $provider,
    'tag_filter' => 'puppetagents'
  )

  $agent_data = $agent_inventory.first.value['value']
  $agent_count = $agent_data.length

  if $agent_count == 0 {
    out::message('⚠ No agent nodes found in tofu state')
    return({ status => 'no_agents', agent_count => 0 })
  }

  out::message("Found ${agent_count} agent node(s) to destroy:")
  $agent_data.each |$agent| {
    out::message("  - ${agent['name']} (${agent['uri']})")
  }
  out::message('')

  # Check if we should proceed with destroy
  unless $confirm {
    out::message('To proceed with destroy, run:')
    out::message('  bolt plan run igor::destroy_agents confirm=true')
    return({
      status => 'plan_only',
      agent_count => $agent_count
    })
  }

  # Get dynamic resource addresses from tofu output
  $provider_dir = "tf/providers/${provider}"
  $addresses_result = run_command(
    "cd ${provider_dir} && tofu output -json client_resource_addresses",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  unless $addresses_result.ok {
    fail_plan("Failed to get client resource addresses: ${addresses_result.first.error}")
  }

  $addresses_json = $addresses_result.first.value['stdout'].strip

  # Build -target flags from the output
  $target_flags_result = run_command(
    "echo '${addresses_json}' | jq -r '.compute[] | \"-target=\" + .' | tr '\\n' ' '",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  $target_flags = $target_flags_result.first.value['stdout'].strip

  # Destroy using OpenTofu with dynamic target flags
  out::message('Running tofu destroy for puppet_clients...')
  $destroy_result = run_command(
    "cd ${provider_dir} && tofu destroy ${target_flags} -auto-approve",
    'localhost',
    '_run_as' => system::env('USER'),
    '_catch_errors' => true
  )

  if $destroy_result.ok {
    out::message('✓ Puppet agent clients destroyed successfully')
    out::message('')
    out::message("Destroyed ${agent_count} agent node(s)")
  } else {
    fail_plan("Failed to destroy clients: ${destroy_result.first.error}")
  }

  return({
    status => 'destroyed',
    agent_count => $agent_count
  })
}
