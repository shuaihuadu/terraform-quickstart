terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "vmss_rg" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "vmss_vnet" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.vmss_rg.location
  resource_group_name = azurerm_resource_group.vmss_rg.name
}

# Subnet
resource "azurerm_subnet" "vmss_subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.vmss_rg.name
  virtual_network_name = azurerm_virtual_network.vmss_vnet.name
  address_prefixes     = var.subnet_address_prefixes
}

# Flexible VMSS with full VM profile (Portal-friendly configuration)
resource "azurerm_orchestrated_virtual_machine_scale_set" "vmss" {
  name                = var.vmss_name
  resource_group_name = azurerm_resource_group.vmss_rg.name
  location            = azurerm_resource_group.vmss_rg.location

  # SKU and Instances - enables Portal manual scaling
  sku_name  = var.vm_size
  instances = var.instance_count

  # Flexible orchestration mode
  platform_fault_domain_count = 1
  single_placement_group      = false
  zones                       = var.zones != null ? var.zones : []

  # OS Profile with VM configuration
  os_profile {
    linux_configuration {
      computer_name_prefix            = var.computer_name_prefix
      admin_username                  = var.admin_username
      admin_password                  = var.admin_password
      disable_password_authentication = false
    }
  }

  # Network Interface Configuration
  network_interface {
    name    = "nic-vmss"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.vmss_subnet.id
    }
  }

  # OS Disk
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  # Source Image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Data Disk (if specified)
  dynamic "data_disk" {
    for_each = var.disk_size_gb != null ? [1] : []
    content {
      lun                  = var.disk_lun
      caching              = "None"
      create_option        = "Empty"
      disk_size_gb         = var.disk_size_gb
      storage_account_type = "PremiumV2_LRS"
      # NOTE: Flexible VMSS does NOT support ultra_ssd parameters in data_disk block
      # ultra_ssd_disk_iops_read_write = var.disk_iops
      # ultra_ssd_disk_mbps_read_write = var.disk_throughput_mbps
    }
  }

  # Tags
  tags = var.tags
}

# Note: This configuration creates a Flexible VMSS with virtualMachineProfile
# - Portal manual scaling: Can adjust instance count in Azure Portal
# - Autoscale support: Can add azurerm_monitor_autoscale_setting later
# - Azure manages VM creation/deletion based on instance count
# - VMs get automatic names like: vmss-name_<instance_id>
# - Up to 1000 instances (Flexible mode maximum)

# Update Premium V2 Disk Performance (Workaround for Flexible VMSS limitation)
# Flexible VMSS doesn't support ultra_ssd parameters in data_disk block,
# so we use Azure CLI to update disk performance after creation
# See: https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-orchestration-modes#unsupported-parameters
resource "null_resource" "update_disk_performance" {
  # Only execute if data_disk is configured with IOPS/throughput parameters
  count = var.disk_size_gb != null && var.disk_iops != null ? 1 : 0

  triggers = {
    vmss_id        = azurerm_orchestrated_virtual_machine_scale_set.vmss.id
    instance_count = var.instance_count
    target_lun     = var.disk_lun
    target_iops    = var.disk_iops
    target_mbps    = var.disk_throughput_mbps
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/update-disk-performance.sh"

    environment = {
      RESOURCE_GROUP   = azurerm_resource_group.vmss_rg.name
      VMSS_NAME        = azurerm_orchestrated_virtual_machine_scale_set.vmss.name
      TARGET_INSTANCES = tostring(var.instance_count)
      TARGET_IOPS      = tostring(var.disk_iops)
      TARGET_MBPS      = tostring(var.disk_throughput_mbps)
      TARGET_LUN       = tostring(var.disk_lun)
      POOL_NAME        = "vmss"
    }
  }

  depends_on = [
    azurerm_orchestrated_virtual_machine_scale_set.vmss
  ]
}
