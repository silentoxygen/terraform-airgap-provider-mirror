#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
MIRROR_DIR="$ROOT_DIR/terraform-providers"

command -v terraform >/dev/null || {
  echo "ERROR: terraform not found"
  exit 1
}

[ -d "$MIRROR_DIR" ] || {
  echo "ERROR: mirror directory does not exist"
  exit 1
}

mapfile -t TF_DIRS < <(
  find . \
    -type f \
    -name main.tf \
    ! -path "./terraform-providers/*" \
    -exec dirname {} \; \
    | sort -u
)

for dir in "${TF_DIRS[@]}"; do
  echo "▶ Mirroring from $dir"

  pushd "$dir" >/dev/null

  terraform init -input=false -upgrade
  terraform providers mirror "$MIRROR_DIR"

  rm -rf .terraform .terraform.lock.hcl

  popd >/dev/null
  echo
done

echo "✔ All providers mirrored successfully"