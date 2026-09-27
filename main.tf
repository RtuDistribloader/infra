locals {
  # Single pool for the base image, the VM disks and the cloud-init ISOs; see
  # the disk_pool note in variables.tf.
  disk_pool = "default"

  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl",
    {
      user           = var.ssh_user
      ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_file)))
  })
}

resource "libvirt_cloudinit_disk" "init" {
  for_each = var.virtual_machines

  name      = "${each.key}-init"
  user_data = local.user_data
  meta_data = yamlencode(
    {
      instance-id    = "${each.key}-${substr(md5(local.user_data), 0, 8)}"
      local-hostname = each.key
  })
}

resource "libvirt_volume" "base" {
  name = "base.qcow2"
  pool = local.disk_pool
  target = {
    format = { type = "qcow2" }
  }
  create = {
    content = { url = var.base_image }
  }
}

resource "libvirt_volume" "disk" {
  for_each = var.virtual_machines

  name     = "${each.key}.qcow2"
  pool     = local.disk_pool
  capacity = each.value.disk_gb * 1024 * 1024 * 1024
  target = {
    format = { type = "qcow2" }
  }
  backing_store = {
    path   = libvirt_volume.base.path
    format = { type = "qcow2" }
  }

}

resource "libvirt_volume" "init" {
  for_each = var.virtual_machines
  name     = "${each.key}-init.iso"
  pool     = local.disk_pool

  # No format here on purpose: the provider uploads the generated ISO and
  # libvirt probes it as "iso". Declaring anything else makes the apply fail
  # with "inconsistent result after apply".
  create = {
    content = { url = libvirt_cloudinit_disk.init[each.key].path }
  }
}

resource "libvirt_domain" "vm" {
  for_each = var.virtual_machines

  name        = each.key
  memory      = each.value.ram_gb
  memory_unit = "GiB"
  vcpu        = each.value.cores
  type        = "kvm"
  running     = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }, { dev = "network" }]
  }

  features = {
    acpi = true
    apic = {}
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.disk[each.key].pool
            volume = libvirt_volume.disk[each.key].name
          }
        }
        target = { bus = "virtio", dev = "vda" }
        driver = { type = "qcow2" }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.init[each.key].pool
            volume = libvirt_volume.init[each.key].name
          }
        }
        target = { bus = "sata", dev = "sda" }
      },
    ]

    interfaces = [
      {
        model = { type = "virtio" }
        source = {
          network = { network = "default" }
        }
        wait_for_ip = { source = "lease" }
      }
    ]

    consoles = [
      {
        type   = "pty"
        target = { type = "serial", port = 0 }
      },
    ]

    graphics = [
      {
        vnc = { auto_port = true, listen = "127.0.0.1" }
      },
    ]
  }
}

data "libvirt_domain_interface_addresses" "vm" {
  for_each = libvirt_domain.vm

  domain = each.value.name
  source = "lease"
}
