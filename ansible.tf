locals {
  # One IPv4 per domain. distinct() collapses an address reported twice; one()
  # then fails the plan if a domain really has two (e.g. a stale DHCP lease
  # next to the live one) rather than picking one at random.
  vm_ipv4 = {
    for name, d in data.libvirt_domain_interface_addresses.vm :
    name => one(distinct(flatten([
      for iface in d.interfaces : [
        for a in iface.addrs : a.addr if a.type == "ipv4"
      ]
    ])))
  }
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/ansible/inventory.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/ansible/inventory.ini.tftpl", {
    vms  = local.vm_ipv4
    user = var.ssh_user
  })
}
