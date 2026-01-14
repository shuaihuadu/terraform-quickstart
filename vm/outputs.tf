output "resource_group_name" {
  description = "资源组名称"
  value       = azurerm_resource_group.vm_rg.name
}

output "vm_id" {
  description = "虚拟机 ID"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "vm_name" {
  description = "虚拟机名称"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "vm_size" {
  description = "虚拟机规格"
  value       = azurerm_linux_virtual_machine.vm.size
}

output "private_ip" {
  description = "私有 IP 地址"
  value       = azurerm_network_interface.vm_nic.private_ip_address
}

output "public_ip" {
  description = "公网 IP 地址"
  value       = var.enable_public_ip ? azurerm_public_ip.vm_pip[0].ip_address : null
}

output "ssh_command" {
  description = "SSH 连接命令"
  value       = var.enable_public_ip ? "ssh ${var.admin_username}@${azurerm_public_ip.vm_pip[0].ip_address}" : "ssh ${var.admin_username}@${azurerm_network_interface.vm_nic.private_ip_address}"
}

output "vnet_id" {
  description = "虚拟网络 ID"
  value       = azurerm_virtual_network.vm_vnet.id
}
