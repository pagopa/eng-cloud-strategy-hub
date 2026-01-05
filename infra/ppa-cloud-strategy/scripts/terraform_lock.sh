#!/bin/bash

# Script to lock Terraform provider versions in all directories with `.tf` files.
# Generates `.terraform.lock.hcl` for macOS and Linux (arm64/amd64).

find . -type f -name "*.tf" -exec dirname {} \; | sort -u | while read -r dir; do
  echo "🔒 Locking providers in: $dir"
  (
    cd "$dir" || exit
    terraform init -backend=false
    terraform providers lock \
      -platform=darwin_arm64 \
      -platform=darwin_amd64 \
      -platform=linux_amd64 \
      -platform=linux_arm64
  ) || echo "❌ Failed to lock providers in: $dir"
done
