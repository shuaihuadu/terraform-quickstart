#!/bin/bash

# Azure Resource Availability Check Script
# Validates VM SKU, Disk SKU, and Zone compatibility before deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Read configuration from terraform.tfvars
TFVARS_FILE="terraform.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}❌ Error: $TFVARS_FILE not found${NC}"
    exit 1
fi

# Parse terraform.tfvars
LOCATION=$(grep '^location' $TFVARS_FILE | sed 's/.*=\s*"\([^"]*\)".*/\1/')
VM_SIZE=$(grep '^vm_size' $TFVARS_FILE | sed 's/.*=\s*"\([^"]*\)".*/\1/')
ZONES=$(grep '^zones' $TFVARS_FILE | sed 's/.*=\s*\[\s*"\([^"]*\)".*/\1/')
DISK_TYPE="PremiumV2_LRS"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Azure Resource Availability Check${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  Location: $LOCATION"
echo "  VM Size: $VM_SIZE"
echo "  Disk Type: $DISK_TYPE"
echo "  Target Zones: $ZONES"
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

CURRENT_SUBSCRIPTION=$(az account show --query "{Name:name, ID:id}" -o tsv)
echo -e "${GREEN}✓ Logged in to Azure${NC}"
echo "  Subscription: $CURRENT_SUBSCRIPTION"
echo ""

# Check VM SKU availability
echo -e "${BLUE}1. Checking VM SKU availability...${NC}"
VM_SKU_JSON=$(az vm list-skus \
    --location "$LOCATION" \
    --size "$VM_SIZE" \
    --all \
    --query "[0]" -o json 2>/dev/null)

if [ "$VM_SKU_JSON" = "null" ] || [ -z "$VM_SKU_JSON" ]; then
    echo -e "${RED}❌ VM SKU '$VM_SIZE' not found in '$LOCATION'${NC}"
    echo ""
    echo -e "${YELLOW}💡 Suggestions:${NC}"
    echo "   - Try a different region (e.g., westus3, westus2, eastus2)"
    echo "   - Use a different VM size (e.g., Standard_D4s_v5)"
    echo ""
    echo "   Available D-series SKUs in $LOCATION:"
    az vm list-skus --location "$LOCATION" --size Standard_D --query "[].name" -o tsv | grep -E "v[5-6]" | sort | head -10
    exit 1
fi

# Check VM restrictions
VM_RESTRICTIONS=$(echo "$VM_SKU_JSON" | jq -r '.restrictions')
if [ "$VM_RESTRICTIONS" != "[]" ] && [ "$VM_RESTRICTIONS" != "null" ]; then
    echo -e "${RED}❌ VM SKU has restrictions in '$LOCATION'${NC}"
    echo "$VM_RESTRICTIONS" | jq .
    
    # Check for zone restrictions
    ZONE_RESTRICTION=$(echo "$VM_RESTRICTIONS" | jq -r '.[] | select(.type=="Zone")')
    if [ -n "$ZONE_RESTRICTION" ]; then
        echo ""
        echo -e "${YELLOW}💡 Zone restrictions detected${NC}"
        echo "   Try: zones = null  (in terraform.tfvars)"
    fi
    exit 1
fi

# Check VM zones
VM_AVAILABLE_ZONES=$(echo "$VM_SKU_JSON" | jq -r '.locationInfo[0].zones[]?' 2>/dev/null | tr '\n' ' ')
if [ -n "$VM_AVAILABLE_ZONES" ]; then
    echo -e "${GREEN}✓ VM SKU '$VM_SIZE' is available${NC}"
    echo "  Available zones: [$(echo $VM_AVAILABLE_ZONES | sed 's/ /, /g')]"
else
    echo -e "${GREEN}✓ VM SKU '$VM_SIZE' is available (no zone info)${NC}"
fi

# Check Disk SKU availability
echo ""
echo -e "${BLUE}2. Checking Disk SKU availability...${NC}"
DISK_SKU_JSON=$(az vm list-skus \
    --location "$LOCATION" \
    --resource-type disks \
    --all \
    --query "[?name=='$DISK_TYPE']" -o json 2>/dev/null)

if [ "$DISK_SKU_JSON" = "[]" ] || [ -z "$DISK_SKU_JSON" ]; then
    echo -e "${RED}❌ Disk type '$DISK_TYPE' not available in '$LOCATION'${NC}"
    echo ""
    echo -e "${YELLOW}💡 Available disk types in $LOCATION:${NC}"
    az vm list-skus --location "$LOCATION" --resource-type disks --query "[].name" -o tsv
    echo ""
    echo -e "${YELLOW}💡 Suggestion: Use Premium_LRS instead of PremiumV2_LRS${NC}"
    exit 1
fi

# Check Disk restrictions
DISK_RESTRICTIONS=$(echo "$DISK_SKU_JSON" | jq -r '.[0].restrictions')
if [ "$DISK_RESTRICTIONS" != "[]" ] && [ "$DISK_RESTRICTIONS" != "null" ]; then
    echo -e "${RED}❌ Disk type has restrictions in '$LOCATION'${NC}"
    echo "$DISK_RESTRICTIONS" | jq .
    exit 1
fi

# Check Disk zones
DISK_AVAILABLE_ZONES=$(echo "$DISK_SKU_JSON" | jq -r '.[0].locationInfo[0].zones[]?' 2>/dev/null | tr '\n' ' ')
if [ -n "$DISK_AVAILABLE_ZONES" ]; then
    echo -e "${GREEN}✓ Disk type '$DISK_TYPE' is available${NC}"
    echo "  Available zones: [$(echo $DISK_AVAILABLE_ZONES | sed 's/ /, /g')]"
else
    echo -e "${GREEN}✓ Disk type '$DISK_TYPE' is available (no zone info)${NC}"
fi

# Check Zone compatibility (if zones specified)
if [ -n "$ZONES" ] && [ "$ZONES" != "null" ]; then
    echo ""
    echo -e "${BLUE}3. Checking Zone compatibility...${NC}"
    
    # Parse zones (handle multiple zones)
    IFS=',' read -ra ZONE_ARRAY <<< "$ZONES"
    
    ZONE_CHECK_FAILED=false
    
    for zone in "${ZONE_ARRAY[@]}"; do
        # Trim whitespace
        zone=$(echo "$zone" | tr -d ' ')
        
        echo "  Checking zone $zone..."
        
        # Check VM zone support
        VM_ZONE_SUPPORTED=false
        if [ -z "$VM_AVAILABLE_ZONES" ] || echo "$VM_AVAILABLE_ZONES" | grep -q "$zone"; then
            VM_ZONE_SUPPORTED=true
        fi
        
        # Check Disk zone support
        DISK_ZONE_SUPPORTED=false
        if [ -z "$DISK_AVAILABLE_ZONES" ] || echo "$DISK_AVAILABLE_ZONES" | grep -q "$zone"; then
            DISK_ZONE_SUPPORTED=true
        fi
        
        if [ "$VM_ZONE_SUPPORTED" = true ] && [ "$DISK_ZONE_SUPPORTED" = true ]; then
            echo -e "    ${GREEN}✓ Zone $zone: Both VM and Disk supported${NC}"
        else
            echo -e "    ${RED}❌ Zone $zone: Incompatible${NC}"
            [ "$VM_ZONE_SUPPORTED" = false ] && echo "       - VM not supported in zone $zone"
            [ "$DISK_ZONE_SUPPORTED" = false ] && echo "       - Disk not supported in zone $zone"
            ZONE_CHECK_FAILED=true
        fi
    done
    
    if [ "$ZONE_CHECK_FAILED" = true ]; then
        echo ""
        echo -e "${YELLOW}💡 Suggestions:${NC}"
        echo "   - Change zones in terraform.tfvars to: zones = [\"$(echo $VM_AVAILABLE_ZONES | cut -d' ' -f1)\"]"
        echo "   - Or disable zones: zones = null"
        exit 1
    fi
else
    echo ""
    echo -e "${BLUE}3. Zone check skipped${NC}"
    echo "  Zones not specified (zones = null)"
fi

# Final summary
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ All checks passed!${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo "You can proceed with deployment:"
echo "  make deploy"
echo ""

exit 0
