variable "base_image" {
  description = "URL or local path of the cloud image every VM is cloned from."
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "virtual_machines" {
  description = "Virtual machines, keyed by name."
  # disk_pool is accepted so the input shape does not have to change once
  # multiple pools are supported, but for now every volume (base image, VM
  # disk, cloud-init ISO) must share one pool -- libvirt backing stores cannot
  # cross pools. Leave it unset.
  type = map(object({
    cores     = number
    ram_gb    = number
    disk_pool = optional(string, "default")
    disk_gb   = number
  }))

  default = {
    vm-1 = {
      cores   = 2
      ram_gb  = 2
      disk_gb = 30
    }
  }

  validation {
    condition     = alltrue([for vm in var.virtual_machines : vm.disk_pool == "default"])
    error_message = "disk_pool must be \"default\": non-default storage pools are not supported yet."
  }
}

variable "ssh_user" {
  description = "User created on every VM; Ansible connects as this user."
  type        = string
  default     = "ansible"
}

variable "ssh_public_key_file" {
  description = "Public key installed for ssh_user on every VM."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
