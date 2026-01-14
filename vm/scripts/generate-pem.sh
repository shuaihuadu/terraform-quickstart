#!/bin/bash
#
# 生成 PEM 格式的私钥文件，便于共享
# 用法: ./generate-pem.sh <username> <public_ip>
#

set -e

USERNAME="$1"
PUBLIC_IP="$2"

if [ -z "$USERNAME" ] || [ -z "$PUBLIC_IP" ]; then
    echo "Usage: $0 <username> <public_ip>"
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="$SCRIPT_DIR/../keys"
SOURCE_KEY="$KEYS_DIR/id_rsa"
PEM_FILE="$KEYS_DIR/${USERNAME}@${PUBLIC_IP}.pem"

# 检查源密钥文件
if [ ! -f "$SOURCE_KEY" ]; then
    echo "Error: Source key not found at $SOURCE_KEY"
    exit 1
fi

# 复制并设置权限
cp "$SOURCE_KEY" "$PEM_FILE"
chmod 600 "$PEM_FILE"

echo "✓ PEM file generated: $PEM_FILE"
echo ""
echo "Usage:"
echo "  ssh -i $PEM_FILE $USERNAME@$PUBLIC_IP"
echo ""
echo "To share with others:"
echo "  1. Securely send the .pem file to the recipient"
echo "  2. They should run: chmod 600 ${USERNAME}@${PUBLIC_IP}.pem"
echo "  3. Then connect: ssh -i ${USERNAME}@${PUBLIC_IP}.pem $USERNAME@$PUBLIC_IP"
