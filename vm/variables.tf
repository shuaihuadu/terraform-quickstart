variable "resource_group_name" {
  description = "资源组名称"
  type        = string
  default     = "rg-vm-demo"
}

variable "location" {
  description = "Azure 区域"
  type        = string
  default     = "westus3"
}

variable "vm_name" {
  description = "虚拟机名称"
  type        = string
  default     = "vm-demo"
}

variable "vm_size" {
  description = "虚拟机规格"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "zone" {
  description = "可用区 (1, 2, 3)，设置为 null 则不使用可用区"
  type        = string
  default     = null
}

# OS Disk
variable "os_disk_size_gb" {
  description = "OS 磁盘大小(GB)"
  type        = number
  default     = 256
}

variable "os_disk_type" {
  description = "OS 磁盘类型"
  type        = string
  default     = "Premium_LRS"
}

# Data Disk
variable "data_disk_size_gb" {
  description = "数据磁盘大小(GB)，设置为 null 则不创建数据磁盘"
  type        = number
  default     = null
}

variable "data_disk_type" {
  description = "数据磁盘类型 (Premium_LRS, PremiumV2_LRS, StandardSSD_LRS)"
  type        = string
  default     = "Premium_LRS"
}

variable "data_disk_iops" {
  description = "数据磁盘 IOPS (仅 PremiumV2_LRS)"
  type        = number
  default     = 3000
}

variable "data_disk_mbps" {
  description = "数据磁盘吞吐量 MB/s (仅 PremiumV2_LRS)"
  type        = number
  default     = 125
}

# Network
variable "vnet_name" {
  description = "虚拟网络名称"
  type        = string
  default     = "vnet-vm"
}

variable "vnet_address_space" {
  description = "虚拟网络地址空间"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_name" {
  description = "子网名称"
  type        = string
  default     = "subnet-vm"
}

variable "subnet_address_prefixes" {
  description = "子网地址前缀"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "enable_public_ip" {
  description = "是否创建公网 IP"
  type        = bool
  default     = true
}

# Authentication
variable "admin_username" {
  description = "管理员用户名"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "管理员密码（至少12个字符，包含大小写字母、数字和特殊字符）。如使用 SSH 公钥则可不填"
  type        = string
  sensitive   = true
  default     = "AzureTest@2026!"
}

variable "ssh_public_key_file" {
  description = "SSH 公钥文件路径 (如 keys/id_rsa.pub)。设置后将禁用密码认证"
  type        = string
  default     = null
}

# Image
variable "image_publisher" {
  description = "镜像发布者"
  type        = string
  default     = "Canonical"
}

variable "image_offer" {
  description = "镜像 Offer"
  type        = string
  default     = "ubuntu-24_04-lts"
}

variable "image_sku" {
  description = "镜像 SKU"
  type        = string
  default     = "server"
}

variable "image_version" {
  description = "镜像版本"
  type        = string
  default     = "latest"
}

# Tags
variable "tags" {
  description = "资源标签"
  type        = map(string)
  default = {
    Environment = "Demo"
    Module      = "vm"
  }
}
