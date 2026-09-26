output "bolt_inventory" {
  description = "All targets in Bolt-consumable format"
  value = concat(
    # PE primary
    var.puppet_pe ? [{
      name = proxmox_vm_qemu.new-puppet-server[0].name
      uri  = regexall("ip=([^/]+)", proxmox_vm_qemu.new-puppet-server[0].ipconfig0)[0][0]
      tags = proxmox_vm_qemu.new-puppet-server[0].tags
    }] : [],
    # SCM
    var.puppet_scm ? [{
      name = proxmox_vm_qemu.new-scm-server[0].name
      uri  = regexall("ip=([^/]+)", proxmox_vm_qemu.new-scm-server[0].ipconfig0)[0][0]
      tags = proxmox_vm_qemu.new-scm-server[0].tags
    }] : [],
    # CD4PE
    var.puppet_cd4pe ? [{
      name = proxmox_vm_qemu.new-cd4pe-server[0].name
      uri  = regexall("ip=([^/]+)", proxmox_vm_qemu.new-cd4pe-server[0].ipconfig0)[0][0]
      tags = proxmox_vm_qemu.new-cd4pe-server[0].tags
    }] : [],
    # Dashboard
    var.puppet_dashboard ? [{
      name = proxmox_vm_qemu.dashboard-server[0].name
      uri  = regexall("ip=([^/]+)", proxmox_vm_qemu.dashboard-server[0].ipconfig0)[0][0]
      tags = proxmox_vm_qemu.dashboard-server[0].tags
    }] : [],
    # Client agents
    [for key, client in proxmox_vm_qemu.puppet_clients : {
      name = client.name
      uri  = regexall("ip=([^/]+)", client.ipconfig0)[0][0]
      tags = client.tags
    }]
  )
}

output "provider_info" {
  description = "Provider metadata for inventory task"
  value = {
    provider = "proxmox"
    domain   = var.domain
    ssh_user = var.ciuser
  }
}

output "client_resource_addresses" {
  description = "Terraform resource addresses for client resources (used by destroy plans)"
  value = {
    compute = [for key, _ in proxmox_vm_qemu.puppet_clients : "proxmox_vm_qemu.puppet_clients[\"${key}\"]"]
  }
}
