# Provider Contract

Every provider implementation must expose these three Terraform outputs so the inventory task and Bolt plans can work identically regardless of the underlying infrastructure platform.

## Required Outputs

### `bolt_inventory`

List of objects representing every managed VM. Each object must contain:

| Field  | Type   | Description                                                      |
| ------ | ------ | ---------------------------------------------------------------- |
| `name` | string | FQDN of the target (must match DNS)                              |
| `uri`  | string | IP address of the target                                         |
| `tags` | string | Semicolon-separated tags (e.g. `puppetinfra;puppet;prod;ubuntu`) |

Example:

```json
[
  {
    "name": "new-puppet.albatrossflavour.com",
    "uri": "192.168.10.100",
    "tags": "puppetinfra;puppet;prod;ubuntu"
  }
]
```

### `provider_info`

Object containing provider metadata:

| Field      | Type   | Description                                          |
| ---------- | ------ | ---------------------------------------------------- |
| `provider` | string | Provider identifier (e.g. `proxmox`, `aws`, `azure`) |
| `domain`   | string | Base DNS domain                                      |
| `ssh_user` | string | Default SSH user for targets                         |

### `client_resource_addresses`

Object containing Terraform resource addresses for client (agent) resources. Used by destroy plans to target specific resources.

| Field     | Type         | Description                              |
| --------- | ------------ | ---------------------------------------- |
| `compute` | list(string) | Resource addresses for compute instances |

Example:

```json
{
  "compute": ["proxmox_vm_qemu.puppet_clients[\"ubuntu-2404-prod-1\"]"]
}
```
