variable "prod_clients" {
  description = "number of puppet production managed clients"
  type        = number
  default     = 0
}

variable "dev_clients" {
  description = "number of puppet dev managed clients"
  type        = number
  default     = 0
}

# OS Distribution Controls
variable "enable_alma" {
  description = "Enable Alma Linux distributions"
  type        = bool
  default     = true
}

variable "enable_centos" {
  description = "Enable CentOS Stream distributions"
  type        = bool
  default     = false
}

variable "enable_debian" {
  description = "Enable Debian distributions"
  type        = bool
  default     = true
}

variable "enable_oracle" {
  description = "Enable Oracle Linux distributions"
  type        = bool
  default     = true
}

variable "enable_redhat" {
  description = "Enable Red Hat Enterprise Linux distributions"
  type        = bool
  default     = false
}

variable "enable_rocky" {
  description = "Enable Rocky Linux distributions"
  type        = bool
  default     = true
}

variable "enable_ubuntu" {
  description = "Enable Ubuntu distributions"
  type        = bool
  default     = true
}

variable "enable_opensuse" {
  description = "Enable OpenSUSE distributions"
  type        = bool
  default     = false
}

variable "enable_amazonlinux" {
  description = "Enable Amazon Linux distributions"
  type        = bool
  default     = false
}

variable "puppet_pe" {
  description = "install and manage puppet enterprise"
  type        = bool
}

variable "puppet_cd4pe" {
  description = "install and manage puppet cd4pe"
  type        = bool
}

variable "puppet_scm" {
  description = "install and manage puppet scm"
  type        = bool
}

variable "puppet_dashboard" {
  description = "install and manage puppet metric dashboard"
  type        = bool
}

variable "api_url" {
  description = "proxmox api endpoint"
  type        = string
}

variable "proxmox_token_id" {
  description = "proxmox token name"
  type        = string
}

variable "proxmox_token_secret" {
  description = "proxmox token secret"
  type        = string
  sensitive   = true
}

variable "disk_size" {
  description = "default disk size"
  type        = string
  default     = "37G"
}

variable "storage_location" {
  description = "default storage location"
  type        = string
  default     = "ceph"
}

variable "cores" {
  description = "default cpu cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "default memory"
  type        = number
  default     = 1536
}

variable "ciuser" {
  description = "default user"
  type        = string
}

variable "cipassword" {
  description = "default password"
  type        = string
  sensitive   = true
}

variable "sshkey" {
  description = "default ssh key"
  type        = string
}

variable "ssh_private_key" {
  description = "private key"
  type        = string
  sensitive   = true
}

variable "console_password" {
  description = "Initial console password"
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Base domain for infrastructure"
  type        = string
  default     = "albatrossflavour.com"
}
