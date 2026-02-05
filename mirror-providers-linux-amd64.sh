#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
MIRROR_DIR="$ROOT_DIR/terraform-providers"
TF_IMAGE="hashicorp/terraform:1.5"

command -v docker >/dev/null || {
  echo "ERROR: docker not found"
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
  echo "▶ Mirroring (linux_amd64) from $dir"

  docker run --rm \
    --platform linux/amd64 \
    -v "$ROOT_DIR:/work" \
    -w "/work/$dir" \
    "$TF_IMAGE" \
    init -input=false -upgrade >/dev/null

  docker run --rm \
    --platform linux/amd64 \
    -v "$ROOT_DIR:/work" \
    -w "/work/$dir" \
    "$TF_IMAGE" \
    providers mirror /work/terraform-providers >/dev/null

  # keep your original cleanup behavior
  rm -rf "$dir/.terraform" "$dir/.terraform.lock.hcl"

  echo
done

echo "✔ All providers mirrored successfully (linux_amd64)"
