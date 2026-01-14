output "resource_group_name" {
  description = "资源组名称"
  value       = azurerm_resource_group.vmss_rg.name
}

output "vmss_id" {
  description = "VMSS ID"
  value       = azurerm_orchestrated_virtual_machine_scale_set.vmss.id
}

output "vmss_name" {
  description = "VMSS名称"
  value       = azurerm_orchestrated_virtual_machine_scale_set.vmss.name
}

output "vmss_sku" {
  description = "VMSS SKU"
  value       = azurerm_orchestrated_virtual_machine_scale_set.vmss.sku_name
}

output "vmss_instances" {
  description = "VMSS实例数"
  value       = azurerm_orchestrated_virtual_machine_scale_set.vmss.instances
}

output "vnet_id" {
  description = "虚拟网络ID"
  value       = azurerm_virtual_network.vmss_vnet.id
}
