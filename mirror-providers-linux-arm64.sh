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
  echo "▶ Mirroring (linux_arm64) from $dir"

  docker run --rm \
    --platform linux/arm64 \
    --entrypoint /bin/sh \
    -v "$ROOT_DIR:/work" \
    -w "/work/$dir" \
    "$TF_IMAGE" \
    -c "terraform init -input=false -upgrade >/dev/null && \
        terraform providers mirror /work/terraform-providers >/dev/null"

  rm -rf "$dir/.terraform" "$dir/.terraform.lock.hcl"
  echo
done

echo "✔ All providers mirrored successfully (linux_arm64)"
