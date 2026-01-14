#!/bin/bash

# Azure Resource Availability Check Script
# 检查 VM SKU 在 region 的可用性
# 检查 Premium SSD V2 在 region + zone 的可用性

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Usage function
show_usage() {
    echo "Usage: $0 <vm-sku> <region> <zones>"
    echo ""
    echo "Examples:"
    echo "  $0 Standard_D4s_v5 westus3 1"
    echo "  $0 Standard_D4s_v5 westus3 1,2,3"
    echo "  $0 Standard_D4s_v6 eastus2 \"1,2\""
    echo ""
    echo "Parameters:"
    echo "  vm-sku  : VM SKU name (e.g., Standard_D4s_v5)"
    echo "  region  : Azure region (e.g., westus3)"
    echo "  zones   : Comma-separated zones or single zone (e.g., 1 or 1,2,3)"
    echo ""
}

# Check parameters
if [ $# -lt 3 ]; then
    echo -e "${RED}❌ Error: Missing required parameters${NC}"
    echo ""
    show_usage
    exit 1
fi

VM_SKU=$1
REGION=$2
ZONES=$3
DISK_TYPE="PremiumV2_LRS"

# Record start time
START_TIME=$(date +%s)
START_TIME_STR=$(date '+%Y-%m-%d %H:%M:%S')

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Azure Resource Availability Check${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "${CYAN}Started at: $START_TIME_STR${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  VM SKU:    $VM_SKU"
echo "  Region:    $REGION"
echo "  Zones:     $ZONES"
echo "  Disk Type: $DISK_TYPE"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI is not installed${NC}"
    echo "Please install it: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Not logged into Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
echo -e "${GREEN}✓ Logged in to Azure${NC}"
echo "  Subscription: $CURRENT_SUBSCRIPTION"
echo ""

# ============================================
# Step 1: Check VM SKU availability in region
# ============================================
echo -e "${BLUE}1. Checking VM SKU availability in region '$REGION'...${NC}"

VM_SKU_JSON=$(az vm list-skus \
    --location "$REGION" \
    --size "$VM_SKU" \
    --all \
    --query "[0]" -o json 2>/dev/null)

if [ "$VM_SKU_JSON" = "null" ] || [ -z "$VM_SKU_JSON" ]; then
    echo -e "${RED}❌ VM SKU '$VM_SKU' not found in region '$REGION'${NC}"
    echo ""
    echo -e "${YELLOW}💡 Available similar SKUs in $REGION:${NC}"
    az vm list-skus --location "$REGION" --size Standard_D --query "[].name" -o tsv 2>/dev/null | grep -E "v[5-6]" | sort | head -10
    exit 1
fi

# Check VM restrictions
VM_RESTRICTIONS=$(echo "$VM_SKU_JSON" | jq -r '.restrictions')
if [ "$VM_RESTRICTIONS" != "[]" ] && [ "$VM_RESTRICTIONS" != "null" ]; then
    echo -e "${RED}❌ VM SKU has restrictions in '$REGION'${NC}"
    echo "$VM_RESTRICTIONS" | jq .
    exit 1
fi

echo -e "${GREEN}✓ VM SKU '$VM_SKU' is available in region '$REGION'${NC}"

# Show VM available zones (informational only)
VM_AVAILABLE_ZONES=$(echo "$VM_SKU_JSON" | jq -r '.locationInfo[0].zones[]?' 2>/dev/null | tr '\n' ' ')
if [ -n "$VM_AVAILABLE_ZONES" ]; then
    echo "  Available zones: [$(echo $VM_AVAILABLE_ZONES | sed 's/ /, /g')]"
else
    echo "  (No zone information - region-wide availability)"
fi

# ============================================
# Step 2: Check Disk availability in region
# ============================================
echo ""
echo -e "${BLUE}2. Checking Disk type '$DISK_TYPE' in region '$REGION'...${NC}"

DISK_SKU_JSON=$(az vm list-skus \
    --location "$REGION" \
    --resource-type disks \
    --all \
    --query "[?name=='$DISK_TYPE']" -o json 2>/dev/null)

if [ "$DISK_SKU_JSON" = "[]" ] || [ -z "$DISK_SKU_JSON" ]; then
    echo -e "${RED}❌ Disk type '$DISK_TYPE' not available in region '$REGION'${NC}"
    echo ""
    echo -e "${YELLOW}💡 This region does not support Premium SSD v2${NC}"
    exit 1
fi

# Check Disk restrictions
DISK_RESTRICTIONS=$(echo "$DISK_SKU_JSON" | jq -r '.[0].restrictions')
if [ "$DISK_RESTRICTIONS" != "[]" ] && [ "$DISK_RESTRICTIONS" != "null" ]; then
    echo -e "${RED}❌ Disk type has restrictions in '$REGION'${NC}"
    echo "$DISK_RESTRICTIONS" | jq .
    exit 1
fi

echo -e "${GREEN}✓ Disk type '$DISK_TYPE' is available in region '$REGION'${NC}"

# Get Disk available zones
DISK_AVAILABLE_ZONES=$(echo "$DISK_SKU_JSON" | jq -r '.[0].locationInfo[0].zones[]?' 2>/dev/null | tr '\n' ' ')
if [ -n "$DISK_AVAILABLE_ZONES" ]; then
    echo "  Available zones: [$(echo $DISK_AVAILABLE_ZONES | sed 's/ /, /g')]"
else
    echo -e "${YELLOW}  ⚠️  No zone information - region-wide only${NC}"
fi

# ============================================
# Step 3: Check Zone compatibility
# ============================================
echo ""
echo -e "${BLUE}3. Checking Zone compatibility...${NC}"
echo -e "${CYAN}   Note: Premium SSD v2 requires BOTH VM and Disk in the SAME zone${NC}"
echo ""

# Parse zones (handle comma-separated values)
IFS=',' read -ra ZONE_ARRAY <<< "$ZONES"

ALL_ZONES_OK=true

for zone in "${ZONE_ARRAY[@]}"; do
    # Trim whitespace
    zone=$(echo "$zone" | tr -d ' ' | tr -d '"')
    
    echo "  Checking zone $zone..."
    
    # Check if Disk supports this zone
    DISK_ZONE_OK=false
    if [ -z "$DISK_AVAILABLE_ZONES" ]; then
        echo -e "    ${RED}❌ Disk does not support zones in this region${NC}"
        ALL_ZONES_OK=false
        continue
    elif echo "$DISK_AVAILABLE_ZONES" | grep -qw "$zone"; then
        DISK_ZONE_OK=true
    else
        echo -e "    ${RED}❌ Disk NOT supported in zone $zone${NC}"
        ALL_ZONES_OK=false
        continue
    fi
    
    # Check if VM supports this zone (if VM has zone info)
    VM_ZONE_OK=false
    if [ -z "$VM_AVAILABLE_ZONES" ]; then
        # VM has no zone info, but that's OK - it can be deployed to any zone
        VM_ZONE_OK=true
        echo -e "    ${YELLOW}⚠️  VM has no zone info (can deploy to any zone)${NC}"
    elif echo "$VM_AVAILABLE_ZONES" | grep -qw "$zone"; then
        VM_ZONE_OK=true
    else
        echo -e "    ${RED}❌ VM NOT supported in zone $zone${NC}"
        ALL_ZONES_OK=false
        continue
    fi
    
    if [ "$DISK_ZONE_OK" = true ] && [ "$VM_ZONE_OK" = true ]; then
        echo -e "    ${GREEN}✓ Zone $zone: Both VM and Disk can be deployed${NC}"
    fi
done

# ============================================
# Final Summary
# ============================================
echo ""
echo -e "${BLUE}======================================${NC}"

if [ "$ALL_ZONES_OK" = true ]; then
    # Calculate elapsed time
    END_TIME=$(date +%s)
    END_TIME_STR=$(date '+%Y-%m-%d %H:%M:%S')
    ELAPSED=$((END_TIME - START_TIME))
    
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo ""
    echo "Summary:"
    echo "  ✓ VM SKU '$VM_SKU' is available in region '$REGION'"
    echo "  ✓ Disk '$DISK_TYPE' is available in region '$REGION'"
    echo "  ✓ Both can be deployed in specified zones: $ZONES"
    echo ""
    echo -e "${CYAN}Important: Deploy VM to the same zone as Premium SSD v2${NC}"
    echo "You can proceed with deployment."
    echo ""
    echo -e "${CYAN}Finished at: $END_TIME_STR (took ${ELAPSED}s)${NC}"
else
    echo -e "${RED}❌ Compatibility check failed${NC}"
    echo ""
    echo "Issues found:"
    echo "  - Some zones do not support VM and/or Disk"
    echo ""
    echo -e "${YELLOW}💡 Suggestions:${NC}"
    
    # Find common zones
    if [ -n "$DISK_AVAILABLE_ZONES" ] && [ -n "$VM_AVAILABLE_ZONES" ]; then
        COMMON_ZONES=""
        for dz in $DISK_AVAILABLE_ZONES; do
            if echo "$VM_AVAILABLE_ZONES" | grep -qw "$dz"; then
                COMMON_ZONES="$COMMON_ZONES$dz "
            fi
        done
        if [ -n "$COMMON_ZONES" ]; then
            echo "  - Use zones that support both VM and Disk: $(echo $COMMON_ZONES | sed 's/ /, /g' | sed 's/, $//')"
        else
            echo "  - No common zones found for both VM and Disk"
        fi
    elif [ -n "$DISK_AVAILABLE_ZONES" ]; then
        echo "  - Use Disk-supported zones: $(echo $DISK_AVAILABLE_ZONES | sed 's/ /, /g')"
    else
        echo "  - Choose a different region that supports Premium SSD v2 with zones"
    fi
    echo ""
    
    # Calculate elapsed time for failure case
    END_TIME=$(date +%s)
    END_TIME_STR=$(date '+%Y-%m-%d %H:%M:%S')
    ELAPSED=$((END_TIME - START_TIME))
    echo -e "${CYAN}Finished at: $END_TIME_STR (took ${ELAPSED}s)${NC}"
    exit 1
fi

echo -e "${BLUE}======================================${NC}"
echo ""

exit 0
