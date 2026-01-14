#!/bin/bash
# Terraform 部署脚本 - 执行 init、plan 和 apply

set -e

# 切换到项目根目录
cd "$(dirname "$0")/.."

echo "=== Terraform Deployment Script ==="
echo "Working directory: $(pwd)"
echo ""

# Step 1: Initialize
echo "=== Step 1: Terraform Init ==="
terraform init
echo "✓ Init completed"
echo ""

# Step 2: Plan and Apply (with auto-approval)
echo "=== Step 2: Terraform Plan & Apply ==="
terraform apply -auto-approve

echo ""
echo "✓ Deployment completed successfully!"
