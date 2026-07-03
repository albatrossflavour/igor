plan igor::status() {
  out::message('=== Puppet Infrastructure Status ===')
  out::message('')

  # Get all infrastructure targets
  $infra_targets = get_targets('puppet-infrastructure')

  if $infra_targets.empty {
    out::message('No infrastructure found in Terraform state.')
    return({})
  }

  # Get agent targets
  $agent_targets = get_targets('puppet-agents')

  out::message("Infrastructure Servers")
  out::message("=====================")
  out::message('')

  # Check each infrastructure component
  $infra_status = $infra_targets.map |$target| {
    $name = $target.name
    $ip = $target.uri
    $tags = $target.vars.get('tags', '')

    # Determine component type from tags (check specific tags first)
    $component = if $tags =~ /;scm(;|$)|(^|;)scm;/ {
      'SCM/Comply'
    } elsif $tags =~ /;cd4pe(;|$)|(^|;)cd4pe;/ {
      'CD4PE'
    } elsif $tags =~ /;dashboard(;|$)|(^|;)dashboard;/ {
      'Dashboard'
    } elsif $tags =~ /;puppet(;|$)|(^|;)puppet;/ and $tags !~ /puppetagents/ {
      'Puppet Enterprise'
    } else {
      'Unknown'
    }

    # Check if host is reachable
    $reachable = run_command('echo ping', $target, '_catch_errors' => true)
    $status = if $reachable.ok {
      # Check service status based on component type
      if $component == 'Puppet Enterprise' {
        $pe_status = run_command('systemctl is-active pe-puppetserver', $target, '_catch_errors' => true)
        if $pe_status.ok and $pe_status.first.value['stdout'] =~ /active/ {
          $version_result = run_command('/opt/puppetlabs/bin/puppetserver --version', $target, '_catch_errors' => true)
          $version = if $version_result.ok {
            $version_result.first.value['stdout'].strip
          } else {
            'unknown'
          }
          "running (${version})"
        } else {
          'service down'
        }
      } elsif $component == 'SCM/Comply' {
        # Use complyadm::ctl to check status
        $scm_result = catch_errors() || {
          run_plan('complyadm::ctl', { 'action' => 'status', 'service' => 'all' })
        }
        if $scm_result =~ Error {
          'service down'
        } else {
          'running'
        }
      } elsif $component == 'CD4PE' {
        # Use cd4peadm::ctl to check status
        $cd4pe_result = catch_errors() || {
          run_plan('cd4peadm::ctl', { 'action' => 'status', 'service' => 'all' })
        }
        if $cd4pe_result =~ Error {
          'service down'
        } else {
          'running'
        }
      } elsif $component == 'Dashboard' {
        $grafana_status = run_command('systemctl is-active grafana-server', $target, '_catch_errors' => true)
        if $grafana_status.ok and $grafana_status.first.value['stdout'] =~ /active/ {
          'running'
        } else {
          'service down'
        }
      } else {
        'running'
      }
    } else {
      'unreachable'
    }

    out::message("${component}: ${name}")
    out::message("  IP: ${ip}")
    out::message("  Status: ${status}")
    out::message('')

    # Return hash for this target
    Hash({
      component => $component,
      name      => $name,
      ip        => $ip,
      status    => $status,
    })
  }

  # Agent summary
  out::message("Puppet Agents")
  out::message("=============")
  out::message('')

  $agent_count = $agent_targets.length
  out::message("Total agents: ${agent_count}")

  if $agent_count > 0 {
    # Count by OS
    $os_counts = $agent_targets.reduce({}) |$memo, $target| {
      $tags = $target.vars.get('tags', '')
      $os = if $tags =~ /ubuntu/ {
        'ubuntu'
      } elsif $tags =~ /alma/ {
        'alma'
      } elsif $tags =~ /centos/ {
        'centos'
      } elsif $tags =~ /debian/ {
        'debian'
      } elsif $tags =~ /oracle/ {
        'oracle'
      } elsif $tags =~ /redhat/ {
        'redhat'
      } elsif $tags =~ /rocky/ {
        'rocky'
      } elsif $tags =~ /opensuse/ {
        'opensuse'
      } elsif $tags =~ /amazonlinux/ {
        'amazonlinux'
      } else {
        'unknown'
      }

      $current = $memo.dig($os).lest || { 0 }
      $memo + { $os => $current + 1 }
    }

    # Count by environment
    $env_counts = $agent_targets.reduce({}) |$memo, $target| {
      $tags = $target.vars.get('tags', '')
      $env = if $tags =~ /prod/ {
        'prod'
      } elsif $tags =~ /dev/ {
        'dev'
      } else {
        'unknown'
      }

      $current = $memo.dig($env).lest || { 0 }
      $memo + { $env => $current + 1 }
    }

    out::message('')
    out::message('By OS:')
    $os_counts.each |$os, $count| {
      out::message("  ${os}: ${count}")
    }

    out::message('')
    out::message('By Environment:')
    $env_counts.each |$env, $count| {
      out::message("  ${env}: ${count}")
    }
  }

  out::message('')

  return({
    infrastructure => $infra_status,
    agents         => {
      total  => $agent_count,
      by_os  => $os_counts,
      by_env => $env_counts,
    }
  })
}
