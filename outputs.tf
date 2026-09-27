output "vm_ips" {
  description = "IPv4 address of every VM, keyed by name."
  value       = local.vm_ipv4
}
