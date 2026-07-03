# @summary Reset Igor configuration back to a clean state
# @param confirm Must be true to actually delete files (default: false = dry run)
# @param provider Infrastructure provider (default: proxmox)
plan igor::reset (
  Boolean $confirm = false,
  String $provider = 'proxmox'
) {

  $project_root = system::env('PWD')
  $provider_dir = "tf/providers/${provider}"

  # Files and directories that setup generates
  $generated_files = [
    "${provider_dir}/terraform.tfvars",
    "${provider_dir}/s3.tfbackend",
    'data/roles/role::pe::primary.yaml',
    'data/roles/role::pe::scm.yaml',
    'data/roles/role::pe::cd4pe.yaml',
    'data/roles/role::pe::dashboard.yaml',
    'data/common.yaml',
    'inventory.yaml',
  ]

  $generated_dirs = [
    'keys',
    '.modules',
    '.resource_types',
    "${provider_dir}/.terraform",
    'downloads',
  ]

  $generated_artifacts = [
    '.plan_cache.json',
    '.task_cache.json',
    '.rerun.json',
    'bolt-debug.log',
    "${provider_dir}/.terraform.lock.hcl",
  ]

  out::message('=== Igor Reset ===')
  out::message('')

  if !$confirm {
    out::message('DRY RUN - showing what would be deleted (use confirm=true to execute)')
    out::message('')
  }

  # Check each file
  $file_checks = $generated_files.map |$file| {
    $check = run_command(
      "test -f ${file} && echo exists || echo missing",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )
    $status = $check.first.value['stdout'].strip
    if $status == 'exists' {
      out::message("  REMOVE: ${file}")
      $file
    } else {
      out::message("  skip:   ${file} (not present)")
      undef
    }
  }.filter |$item| { $item != undef }

  # Check each directory
  $dir_checks = $generated_dirs.map |$dir| {
    $check = run_command(
      "test -d ${dir} && echo exists || echo missing",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )
    $status = $check.first.value['stdout'].strip
    if $status == 'exists' {
      out::message("  REMOVE: ${dir}/")
      $dir
    } else {
      out::message("  skip:   ${dir}/ (not present)")
      undef
    }
  }.filter |$item| { $item != undef }

  # Check artifacts
  $artifact_checks = $generated_artifacts.map |$file| {
    $check = run_command(
      "test -f ${file} && echo exists || echo missing",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )
    $status = $check.first.value['stdout'].strip
    if $status == 'exists' {
      out::message("  REMOVE: ${file}")
      $file
    } else {
      undef
    }
  }.filter |$item| { $item != undef }

  $all_files = $file_checks + $artifact_checks
  $all_dirs = $dir_checks

  $total_count = $all_files.length + $all_dirs.length

  out::message('')

  if $total_count == 0 {
    out::message('Nothing to reset - already clean.')
    return({ 'status' => 'clean', 'removed_files' => 0, 'removed_dirs' => 0 })
  }

  out::message("Total: ${all_files.length} files, ${all_dirs.length} directories to remove")

  unless $confirm {
    out::message('')
    out::message('To execute this reset, run:')
    out::message('  bolt plan run igor::reset confirm=true')
    return({ 'status' => 'dry_run', 'would_remove_files' => $all_files.length, 'would_remove_dirs' => $all_dirs.length })
  }

  out::message('')
  out::message('Removing files and directories...')

  # Remove files
  $all_files.each |$file| {
    run_command(
      "rm -f ${file}",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )
  }

  # Remove directories
  $all_dirs.each |$dir| {
    run_command(
      "rm -rf ${dir}",
      'localhost',
      '_run_as' => system::env('USER'),
      '_catch_errors' => true
    )
  }

  out::message('')
  out::message('=== Reset Complete ===')
  out::message('')
  out::message('Igor has been reset to a clean state.')
  out::message('To reconfigure, run:')
  out::message('  ./igor setup')
  out::message('')

  return({
    'status' => 'completed',
    'removed_files' => $all_files.length,
    'removed_dirs' => $all_dirs.length
  })
}
