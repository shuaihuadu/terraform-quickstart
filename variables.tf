variable "resource_group_name" {
  description = "资源组名称"
  type        = string
  default     = "rg-vmss-pdv2"
}

variable "location" {
  description = "Azure区域"
  type        = string
  default     = "westus3"
}

variable "vm_size" {
  description = "虚拟机规格"
  type        = string
  default     = "Standard_D4s_v6"
}

variable "instance_count" {
  description = "VMSS实例数量"
  type        = number
  default     = 1
}

variable "zones" {
  description = "可用区列表，设置为 null 则不使用可用区"
  type        = list(string)
  default     = ["3"]
}

variable "disk_lun" {
  description = "数据磁盘 LUN 编号"
  type        = number
  default     = 0
}

variable "disk_size_gb" {
  description = "Premium Disk v2 大小(GB)，设置为 null 则不创建数据磁盘"
  type        = number
  default     = 100
}

variable "disk_iops" {
  description = "Premium Disk v2 IOPS"
  type        = number
  default     = 16000
}

variable "disk_throughput_mbps" {
  description = "Premium Disk v2 吞吐量(MB/s)"
  type        = number
  default     = 1000
}

variable "admin_username" {
  description = "管理员用户名"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "管理员密码（至少12个字符，包含大小写字母、数字和特殊字符）"
  type        = string
  sensitive   = true
  default     = "AzureTest@2026!"
}
