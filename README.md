# Airgapped Terraform Provider Repository

![Terraform Airgap Provider Mirror Logo](assets/logo.png)

A complete setup for creating and serving Terraform providers in an airgapped (offline) environment. This project enables you to mirror Terraform providers locally and serve them through a secure Docker-based network, allowing Terraform to work without external internet access.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Project Layout](#project-layout-important-paths)
- [Quick Start](#quick-start-recommended-flow)
- [Certificate Management](#certificate-management)
- [Testing with tf-client](#testing-with-tf-client)
- [Troubleshooting](#troubleshooting)
- [Provider Mirroring Details](#provider-mirroring-details)
- [Syncing Updates](#syncing-updates)
- [Advanced Topics](#advanced-topics)

## Overview

This project provides:

- **Provider Mirroring**: Scripts to download and mirror Terraform providers from the official registry
- **Offline Server**: An HTTPS-enabled Nginx server that serves providers in an airgapped network
- **Client Container**: A Terraform client container configured to use the local mirror
- **Multi-Version Support**: Examples of mirroring multiple versions of the same provider

**Use Cases:**
- Secure, isolated environments with no external internet access
- Compliance requirements for offline infrastructure
- Reduced network bandwidth and faster provider initialization
- Consistent provider versions across deployments

## Prerequisites

- Docker installed and working
- (Optional) `terraform` CLI if you prefer to run mirroring natively instead of via Docker

## Project layout (important paths)

- `tf-mirror-server/` — Dockerfile, `nginx-mirror.conf`, server build context
- `tf-client/` — Dockerfile for the client, `terraform.rc`, example `main.tf`, destination for `mirror.crt`
- `terraform-providers/` — generated provider cache produced by the mirror scripts
- `mirror-providers-*.sh` — helper scripts that run `terraform` to download providers into the cache

## Quick start (recommended flow)

1) Mirror providers (run on a host that can reach the internet):

```bash
chmod +x mirror-providers-*.sh
./mirror-providers-mac.sh   # or the appropriate script for your platform
```

This creates `terraform-providers/registry.terraform.io/...` with provider metadata and binaries.

2) Build the mirror server image:

```bash
docker build -t tf-mirror-server ./tf-mirror-server
```

3) Create the isolated Docker network:

```bash
docker network create tf-network
```

4) Start the mirror server (detached):

```bash
docker run -d --name tf-mirror --network tf-network -p 443:443 tf-mirror-server
```

5) Copy the server certificate into `tf-client` and build the client image:

```bash
# Copy certificate from running container into the tf-client folder
docker cp tf-mirror:/etc/nginx/certs/mirror.crt ./tf-client/mirror.crt

# Build the client image (this bakes the cert into the image's CA store)
docker build -t tf-client ./tf-client
```

6) (Recommended) Generate a multi-platform lock file so other architectures can verify provider checksums — see the Lockfile section below.

7) Run the client to `init` the example workspace:

```bash
docker run --rm --network tf-network -v $(pwd)/tf-client:/work -w /work tf-client init
```

## Certificate management

The server builds a self-signed certificate at `/etc/nginx/certs/mirror.crt` inside the container. The client image installs this certificate into the system CA bundle (see `tf-client/Dockerfile`) so `terraform` can verify the mirror's TLS.

Recommended workflow:

1. Start the `tf-mirror` container.
2. Copy the certificate into `tf-client/mirror.crt` using `docker cp`.
3. Rebuild `tf-client` so the certificate is present at image build time and gets installed into the CA store.

Alternative: mount the certificate into the client container at runtime (avoids rebuilding), or provision a shared volume between containers.

## Testing with `tf-client`

Basic: run `terraform init` in the example workspace using the client image:

```bash
docker run --rm --network tf-network -v $(pwd)/tf-client:/work -w /work tf-client init
```

Interactive shell (debugging):

```bash
docker run -it --rm --network tf-network -v $(pwd)/tf-client:/work -w /work tf-client /bin/sh
```

Inside the container you can run `curl -v --cacert /usr/local/share/ca-certificates/tf-mirror.crt https://tf-mirror/` and `terraform init`/`plan`.

**Enable verbose logging:**
```bash
docker run --rm \
  --network tf-network \
  -e TF_LOG=DEBUG \
  -v $(pwd)/tf-client:/work \
  -w /work \
  tf-client \
  init
```

**Check provider cache:**
```bash
docker exec tf-client find .terraform -type f -name "*.json"
```

## Troubleshooting

Common checks:

- Ensure both containers are on `tf-network`: `docker network inspect tf-network`
- Check `tf-mirror` is running: `docker ps | grep tf-mirror`
- Test connectivity from client: `docker exec tf-client curl -k https://tf-mirror/`

### Incomplete lock file information for providers

**Warning message you may see:**

```
Incomplete lock file information for providers
```

Cause:

- Terraform generates provider checksums for the platform used when running `terraform init` or `providers lock`.
- If you generate the lock file from a `linux_arm64` client, `.terraform.lock.hcl` will contain only `linux_arm64` checksums.
- Running the same config on other platforms (e.g., `linux_amd64`, `darwin_arm64`, `darwin_amd64`) will fail because checksums for those platforms are missing.

Solution — create a multi-platform lock file:

Run this from your repository root using a trusted client container that can reach the mirror. It adds platform-specific checksums to `.terraform.lock.hcl`:

```bash
docker run --rm -it \
  --network tf-network \
  -v "$PWD/tf-client:/work" \
  -w /work \
  tf-client-trusted \
  providers lock \
  -platform=linux_amd64 \
  -platform=linux_arm64 \
  -platform=darwin_arm64
```

This updates `.terraform.lock.hcl` with checksums for the listed platforms. Commit `.terraform.lock.hcl` to version control so other platforms can verify provider downloads from the mirror.

### Common errors & fixes

- `ssl: certificate verify failed` — ensure `mirror.crt` was copied into `tf-client` and the client image was rebuilt.
- `dial tcp: lookup tf-mirror: no such host` — verify both containers use the `tf-network` network and the client resolves `tf-mirror`.
- `Failed to download provider` — verify the provider/version exists under `terraform-providers/registry.terraform.io/hashicorp/` and the mirror was built with that content.

## Provider Mirroring Details

Use `terraform providers mirror` to produce the `terraform-providers/` structure. Example:

```bash
openssl verify -CAfile mirror.crt mirror.crt
```

The mirror layout follows Terraform's registry layout under `terraform-providers/registry.terraform.io/hashicorp/<provider>/<version>/`.

## Syncing Updates

To update providers:

1. Update version constraints in the relevant `main.tf` files under provider example directories.
2. Re-run the mirror script or `terraform providers mirror` to refresh `terraform-providers/`.
3. Rebuild the `tf-mirror-server` image and restart `tf-mirror`.

## Advanced Topics

### Custom Provider Registry

To host non-HashiCorp providers:

1. Add a new directory structure:
   ```bash
   mkdir -p terraform-providers/example.com/myorg/myprovider/
   ```

2. Add version metadata JSON files (following Terraform Registry API)

3. Update `terraform.rc` to include the custom namespace
