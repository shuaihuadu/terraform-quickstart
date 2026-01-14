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
resource "azurerm_resource_group" "vm_rg" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "vm_vnet" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name
}

# Subnet
resource "azurerm_subnet" "vm_subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.vm_rg.name
  virtual_network_name = azurerm_virtual_network.vm_vnet.name
  address_prefixes     = var.subnet_address_prefixes
}

# Public IP (optional)
resource "azurerm_public_ip" "vm_pip" {
  count               = var.enable_public_ip ? 1 : 0
  name                = "${var.vm_name}-pip"
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zone != null ? [var.zone] : null
}

# Network Interface
resource "azurerm_network_interface" "vm_nic" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_public_ip ? azurerm_public_ip.vm_pip[0].id : null
  }
}

# Network Security Group
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name

  # SSH access
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "vm_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# Azure SSH 公钥资源 (独立资源，可在 Portal 中查看和复用)
resource "azurerm_ssh_public_key" "vm_ssh_key" {
  count               = var.ssh_public_key_file != null ? 1 : 0
  name                = "${var.vm_name}_key"
  resource_group_name = azurerm_resource_group.vm_rg.name
  location            = azurerm_resource_group.vm_rg.location
  public_key          = file(var.ssh_public_key_file)

  tags = var.tags
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.vm_rg.name
  location            = azurerm_resource_group.vm_rg.location
  size                = var.vm_size
  zone                = var.zone

  admin_username                  = var.admin_username
  admin_password                  = var.ssh_public_key_file != null ? null : var.admin_password
  disable_password_authentication = var.ssh_public_key_file != null

  # SSH 公钥认证 (使用 Azure SSH 密钥资源)
  dynamic "admin_ssh_key" {
    for_each = var.ssh_public_key_file != null ? [1] : []
    content {
      username   = var.admin_username
      public_key = azurerm_ssh_public_key.vm_ssh_key[0].public_key
    }
  }

  network_interface_ids = [
    azurerm_network_interface.vm_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  tags = var.tags
}

# Data Disk (optional)
resource "azurerm_managed_disk" "data_disk" {
  count                = var.data_disk_size_gb != null ? 1 : 0
  name                 = "${var.vm_name}-datadisk"
  location             = azurerm_resource_group.vm_rg.location
  resource_group_name  = azurerm_resource_group.vm_rg.name
  storage_account_type = var.data_disk_type
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  zone                 = var.zone

  # Premium SSD v2 performance settings
  disk_iops_read_write = var.data_disk_type == "PremiumV2_LRS" ? var.data_disk_iops : null
  disk_mbps_read_write = var.data_disk_type == "PremiumV2_LRS" ? var.data_disk_mbps : null

  tags = var.tags
}

# Attach Data Disk
resource "azurerm_virtual_machine_data_disk_attachment" "data_disk_attach" {
  count              = var.data_disk_size_gb != null ? 1 : 0
  managed_disk_id    = azurerm_managed_disk.data_disk[0].id
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  lun                = 0
  caching            = var.data_disk_type == "PremiumV2_LRS" ? "None" : "ReadWrite"
}

# 部署后配置：设置用户密码
resource "null_resource" "set_user_password" {
  count = var.ssh_public_key_file != null && fileexists(".env") ? 1 : 0

  triggers = {
    vm_id = azurerm_linux_virtual_machine.vm.id
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/set-password.sh ${azurerm_resource_group.vm_rg.name} ${azurerm_linux_virtual_machine.vm.name} ${var.admin_username}"
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm
  ]
}

# 部署后配置：生成 PEM 文件
resource "null_resource" "generate_pem" {
  count = var.ssh_public_key_file != null && var.enable_public_ip ? 1 : 0

  triggers = {
    vm_id = azurerm_linux_virtual_machine.vm.id
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/generate-pem.sh ${var.admin_username} ${azurerm_public_ip.vm_pip[0].ip_address}"
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm,
    azurerm_public_ip.vm_pip
  ]
}
