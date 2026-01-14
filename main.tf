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
    command = <<-EOT
      set -e
      echo "=== Updating Premium V2 Disk performance for VMSS ==="
      
      RG="${azurerm_resource_group.vmss_rg.name}"
      VMSS_NAME="${azurerm_orchestrated_virtual_machine_scale_set.vmss.name}"
      TARGET_LUN="${var.disk_lun}"
      MAX_RETRIES=30
      RETRY_INTERVAL=10
      
      # Function to wait for VMs to be ready
      # Note: Flexible VMSS uses az vm list instead of az vmss list-instances
      # Log messages go to stderr, only instance names go to stdout
      wait_for_vms() {
        echo "Waiting for VMSS instances to be ready..." >&2
        for i in $(seq 1 $MAX_RETRIES); do
          # For Flexible VMSS, use az vm list filtered by VMSS prefix
          INSTANCES=$(az vm list \
            --resource-group "$RG" \
            --query "[?starts_with(name, '$VMSS_NAME') && provisioningState=='Succeeded'].name" -o tsv 2>/dev/null || true)
          
          INSTANCE_COUNT=$(echo "$INSTANCES" | grep -c . || echo 0)
          if [ -n "$INSTANCES" ] && [ "$INSTANCE_COUNT" -eq "${var.instance_count}" ]; then
            echo "✓ All $INSTANCE_COUNT instances are ready" >&2
            echo "$INSTANCES"  # Only this goes to stdout
            return 0
          fi
          
          echo "Attempt $i/$MAX_RETRIES: Found $INSTANCE_COUNT/${var.instance_count} ready instances, waiting..." >&2
          sleep $RETRY_INTERVAL
        done
        
        echo "❌ Timeout waiting for VMSS instances" >&2
        exit 1
      }
      
      # Function to wait for disk to be attached and ready
      # Log messages go to stderr, only disk name goes to stdout
      wait_for_disk() {
        local VM_NAME=$1
        local MAX_DISK_RETRIES=20
        
        for i in $(seq 1 $MAX_DISK_RETRIES); do
          DISK_NAME=$(az vm show \
            --resource-group "$RG" \
            --name "$VM_NAME" \
            --query "storageProfile.dataDisks[?lun==\`$TARGET_LUN\`].name" -o tsv 2>/dev/null || true)
          
          if [ -n "$DISK_NAME" ]; then
            # Check disk state
            DISK_STATE=$(az disk show \
              --resource-group "$RG" \
              --name "$DISK_NAME" \
              --query "{provisioningState:provisioningState, diskState:diskState}" -o json 2>/dev/null || true)
            
            PROV_STATE=$(echo "$DISK_STATE" | jq -r '.provisioningState // "Unknown"')
            DISK_STATUS=$(echo "$DISK_STATE" | jq -r '.diskState // "Unknown"')
            
            if [ "$PROV_STATE" = "Succeeded" ] && [ "$DISK_STATUS" = "Attached" ]; then
              echo "$DISK_NAME"  # Only this goes to stdout
              return 0
            fi
            
            echo "  Disk $DISK_NAME state: $PROV_STATE/$DISK_STATUS, waiting..." >&2
          fi
          
          sleep 5
        done
        
        return 1
      }
      
      # Wait for all VMs to be ready
      INSTANCES=$(wait_for_vms)
      
      # Update disk performance for each instance
      SUCCESS_COUNT=0
      FAIL_COUNT=0
      
      for VM_NAME in $INSTANCES; do
        echo ""
        echo "Processing VM: $VM_NAME"
        
        # Wait for disk to be attached and ready
        DISK_NAME=$(wait_for_disk "$VM_NAME")
        
        if [ -z "$DISK_NAME" ]; then
          echo "  ❌ Failed to find ready disk on LUN $TARGET_LUN for $VM_NAME"
          FAIL_COUNT=$((FAIL_COUNT + 1))
          continue
        fi
        
        echo "  Found disk: $DISK_NAME on LUN $TARGET_LUN (ready)"
        
        # Update disk performance parameters (without --no-wait to ensure completion)
        echo "  Updating IOPS to ${var.disk_iops}, throughput to ${var.disk_throughput_mbps} MB/s..."
        if az disk update \
          --resource-group "$RG" \
          --name "$DISK_NAME" \
          --disk-iops-read-write ${var.disk_iops} \
          --disk-mbps-read-write ${var.disk_throughput_mbps} \
          --output none 2>&1; then
          
          # Verify the update
          VERIFY=$(az disk show \
            --resource-group "$RG" \
            --name "$DISK_NAME" \
            --query "{IOPS:diskIOPSReadWrite, MBPS:diskMBpsReadWrite}" -o json)
          
          ACTUAL_IOPS=$(echo "$VERIFY" | jq -r '.IOPS')
          ACTUAL_MBPS=$(echo "$VERIFY" | jq -r '.MBPS')
          
          if [ "$ACTUAL_IOPS" -eq "${var.disk_iops}" ] && [ "$ACTUAL_MBPS" -eq "${var.disk_throughput_mbps}" ]; then
            echo "  ✅ Successfully updated and verified: $DISK_NAME"
            echo "     IOPS: $ACTUAL_IOPS, Throughput: $ACTUAL_MBPS MB/s"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
          else
            echo "  ⚠️  Update command succeeded but values don't match:"
            echo "     Expected: ${var.disk_iops} IOPS, ${var.disk_throughput_mbps} MB/s"
            echo "     Actual: $ACTUAL_IOPS IOPS, $ACTUAL_MBPS MB/s"
            FAIL_COUNT=$((FAIL_COUNT + 1))
          fi
        else
          echo "  ❌ Failed to update disk $DISK_NAME"
          FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
      done
      
      echo ""
      echo "=== Update Summary ==="
      echo "Successfully updated: $SUCCESS_COUNT disks"
      echo "Failed: $FAIL_COUNT disks"
      
      if [ $FAIL_COUNT -gt 0 ]; then
        echo "⚠️  Some disk updates failed. Please check the logs above."
        exit 1
      fi
      
      echo "✅ All disk performance parameters updated successfully"
    EOT
  }

  depends_on = [
    azurerm_orchestrated_virtual_machine_scale_set.vmss
  ]
}
