#!/bin/bash
# Terraform 清理脚本 - 删除本地状态和缓存文件

set -e

# 切换到项目根目录
cd "$(dirname "$0")/.."

echo "=== Cleaning Terraform files in $(pwd) ==="

# 删除 .terraform 目录
if [ -d ".terraform" ]; then
  echo "Removing .terraform directory..."
  rm -rf .terraform
  echo "✓ Removed .terraform"
else
  echo "⊘ .terraform not found"
fi

# 删除 .terraform.lock.hcl
if [ -f ".terraform.lock.hcl" ]; then
  echo "Removing .terraform.lock.hcl..."
  rm -f .terraform.lock.hcl
  echo "✓ Removed .terraform.lock.hcl"
else
  echo "⊘ .terraform.lock.hcl not found"
fi

# 删除 terraform.tfstate
if [ -f "terraform.tfstate" ]; then
  echo "Removing terraform.tfstate..."
  rm -f terraform.tfstate
  echo "✓ Removed terraform.tfstate"
else
  echo "⊘ terraform.tfstate not found"
fi

# 删除 terraform.tfstate.backup
if [ -f "terraform.tfstate.backup" ]; then
  echo "Removing terraform.tfstate.backup..."
  rm -f terraform.tfstate.backup
  echo "✓ Removed terraform.tfstate.backup"
else
  echo "⊘ terraform.tfstate.backup not found"
fi

echo ""
echo "=== Cleanup completed ==="
echo "You can now run 'terraform init' to start fresh."
