#!/bin/bash
#
# 设置 VM 用户密码
# 用法: ./set-password.sh <resource_group> <vm_name> <username>
#

set -e

RESOURCE_GROUP="$1"
VM_NAME="$2"
USERNAME="$3"

if [ -z "$RESOURCE_GROUP" ] || [ -z "$VM_NAME" ] || [ -z "$USERNAME" ]; then
    echo "Usage: $0 <resource_group> <vm_name> <username>"
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# 从 .env 文件读取密码
if [ -f "$ENV_FILE" ]; then
    # 使用 . 代替 source 以兼容 sh
    . "$ENV_FILE"
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    echo "Error: PASSWORD not set in .env file"
    exit 1
fi

# 等待 VM 完全就绪
echo "Waiting for VM to be ready..."
sleep 30

# 使用 Azure CLI 通过 run-command 设置密码
echo "Setting password for user $USERNAME..."
az vm run-command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts "echo '$USERNAME':'$PASSWORD' | sudo chpasswd" \
    --output none

echo "✓ Password set successfully for user $USERNAME"
