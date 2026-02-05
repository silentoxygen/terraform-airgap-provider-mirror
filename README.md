# Airgapped Terraform Provider Repository

![Terraform Airgap Provider Mirror Logo](assets/logo.png)

A complete setup for creating and serving Terraform providers in an airgapped (offline) environment. This project enables you to mirror Terraform providers locally and serve them through a secure Docker-based network, allowing Terraform to work without external internet access.

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [Provider Mirroring](#provider-mirroring)
- [Docker Network Setup](#docker-network-setup)
- [Certificate Management](#certificate-management)
- [Testing with tf-client](#testing-with-tf-client)
- [Troubleshooting](#troubleshooting)

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

## Project Structure
# Airgapped Terraform Provider Mirror

A focused repository for mirroring Terraform providers and serving them from an HTTPS-enabled local mirror for airgapped or restricted environments. The README below shows a minimal, robust workflow to create the mirror, start a secure server, and run a trusted client against it.

## Contents

- Overview
- Prerequisites
- Project layout
- Quick start (mirror → server → client)
- Certificate management
- Testing and troubleshooting
- Provider mirroring details
- Syncing updates & contributing

## Overview

This project provides:

- A local provider cache produced by `terraform providers mirror` stored in `terraform-providers/`
- An HTTPS Nginx-based mirror image built from `tf-mirror-server/` that serves the cache
- A `tf-client/` Docker image and test workspace that uses the mirror via `terraform.rc`

Primary goals:

- Allow Terraform to run in environments without external access
- Ensure reproducible provider versions via a local registry and lock file
- Provide a minimal, auditable workflow for extracting and trusting the mirror's certificate

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

## Provider mirroring details

Use `terraform providers mirror` to produce the `terraform-providers/` structure. Example:

```bash
```bash
openssl verify -CAfile mirror.crt mirror.crt
```

The mirror layout follows Terraform's registry layout under `terraform-providers/registry.terraform.io/hashicorp/<provider>/<version>/`.

## Syncing updates

To update providers:

1. Update version constraints in the relevant `main.tf` files under provider example directories.
2. Re-run the mirror script or `terraform providers mirror` to refresh `terraform-providers/`.
3. Rebuild the `tf-mirror-server` image and restart `tf-mirror`.

## Contributing

To add a new provider or version:

1. Add a directory with a `main.tf` that declares the required provider.
2. Run the mirror script to download provider files.
3. Rebuild the mirror server and test with `tf-client`.

If you'd like, I can also add a short section documenting how to build a `tf-client-trusted` image used for producing multi-platform lockfiles.  


**Test HTTPS connection:**
```bash
curl -v --cacert mirror.crt https://tf-mirror/
```

## Testing with tf-client

### Simple Test: terraform init

**Basic initialization test:**
```bash
docker run --rm \
  --network tf-network \
  -v $(pwd)/tf-client:/work \
  -w /work \
  tf-client \
  init
```

**Expected output:**
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws version matching "5.100.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (...)

Terraform has been successfully configured!
```

### Detailed Testing

**Interactive session with shell access:**
```bash
docker run -it \
  --network tf-network \
  -v $(pwd)/tf-client:/work \
  -w /work \
  tf-client \
  /bin/sh
```

**Inside the container, test:**
```bash
# View Terraform configuration
cat terraform.rc

# Test HTTPS connectivity to mirror
curl -v https://tf-mirror/

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Display plan (read-only)
terraform plan
```

### Debugging Provider Download

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

**Verify mirror connectivity from client:**
```bash
docker exec tf-client curl -k -I https://tf-mirror/registry.terraform.io/hashicorp/aws/5.100.0.json
```

## Troubleshooting

### Mirror Server Issues

**Problem: Certificate validation fails**
```
ssl: certificate verify failed
```

**Solution:**
1. Verify certificate was copied correctly:
   ```bash
   docker cp tf-mirror:/etc/nginx/certs/mirror.crt ./mirror.crt
   ls -la mirror.crt
   ```

2. Rebuild the client:
   ```bash
   docker build -t tf-client ./tf-client
   ```

3. Verify certificate is installed:
   ```bash
   docker exec tf-client openssl x509 -in /usr/local/share/ca-certificates/tf-mirror.crt -text
   ```

**Problem: Cannot reach mirror server**
```
dial tcp: lookup tf-mirror: no such host
```

**Solution:**
1. Verify both containers are on the same network:
   ```bash
   docker network inspect tf-network
   ```

2. Check if mirror container is running:
   ```bash
   docker ps | grep tf-mirror
   ```

3. Test connectivity:
   ```bash
   docker exec tf-client ping -c 1 tf-mirror
   ```

### Provider Download Issues

**Problem: Provider version not found**
```
Failed to download provider hashicorp/aws v5.100.0
```

**Solution:**
1. Verify provider is in mirror directory:
   ```bash
   ls terraform-providers/registry.terraform.io/hashicorp/aws/
   ```

2. Check if mirror script completed successfully:
   ```bash
   ./mirror-providers-mac.sh
   ```

3. Rebuild mirror server image:
   ```bash
   docker build --no-cache -t tf-mirror-server ./tf-mirror-server
   ```

**Problem: Mirroring script fails**
```
ERROR: mirror directory does not exist
```

**Solution:**
1. Create the mirror directory:
   ```bash
   mkdir -p terraform-providers
   ```

2. Ensure script has correct permissions:
   ```bash
   chmod +x mirror-providers-*.sh
   ```

3. Verify you're in the correct directory:
   ```bash
   pwd  # Should be the repo root
   ```

### Lock file platform checksums

**Warning:**

```
Incomplete lock file information for providers
```

Reason:

- Terraform generated checksums only for the platform that ran `terraform init`.
- If your trusted client container platform = `linux_arm64`, the lock file will contain only `linux_arm64` hashes.
- If someone later runs the same configuration on `linux_amd64`, `darwin_arm64`, or `darwin_amd64`, Terraform will fail because checksums for those platforms are missing.

This is expected when using mirrors or custom install methods because provider checksums are platform-specific.

Generate a multi-platform lock file

Run this once in your `tf-client` directory (using a trusted client container that can reach the mirror). The command adds checksums for each specified platform to `.terraform.lock.hcl`:

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

This updates `.terraform.lock.hcl` to include checksums for the listed platforms. Commit that file to version control so other platforms can verify provider downloads from the mirror.


### Network Isolation Testing

**Verify airgapped setup works:**
```bash
# Start mirror and client
docker run -d --name tf-mirror --network tf-network tf-mirror-server
docker run -d --name tf-client --network tf-network -v $(pwd)/tf-client:/work tf-client sleep 3600

# Verify containers can't reach external internet
docker exec tf-client curl -I https://registry.terraform.io/
# Should timeout/fail

# Verify they can reach each other
docker exec tf-client curl -k https://tf-mirror/
# Should succeed
```

## Advanced Topics

### Hosting Behind a Load Balancer

The nginx mirror server can be deployed behind load balancers for HA:

```yaml
services:
  tf-mirror-1:
    build: ./tf-mirror-server
    networks:
      - tf-network

  tf-mirror-2:
    build: ./tf-mirror-server
    networks:
      - tf-network

  haproxy:
    image: haproxy:latest
    networks:
      - tf-network
    ports:
      - "443:443"
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
```

Point `terraform.rc` to the load balancer endpoint.

### Syncing Updates

To update providers to newer versions:

```bash
# Update provider versions in main.tf files
vim aws/v5/main.tf  # Change version constraint

# Re-run mirror script
./mirror-providers-mac.sh

# Rebuild mirror server
docker build -t tf-mirror-server ./tf-mirror-server

# Restart containers
docker-compose down
docker-compose up -d
```

### Custom Provider Registry

To host non-HashiCorp providers:

1. Add a new directory structure:
   ```bash
   mkdir -p terraform-providers/example.com/myorg/myprovider/
   ```

2. Add version metadata JSON files (following Terraform Registry API)

3. Update `terraform.rc` to include the custom namespace

## Contributing

To add new providers or versions:

1. Create a provider directory: `mkdir -p provider-name/version`
2. Add a `main.tf` with provider requirements
3. Run the mirror script
4. Rebuild Docker images
5. Test with tf-client

## License

This project is provided as-is for airgapped Terraform deployments.

## References

- [Terraform Provider Mirror Documentation](https://www.terraform.io/cli/commands/providers/mirror)
- [Terraform CLI Configuration](https://www.terraform.io/cli/config)
- [Terraform Network Mirror Provider Installation](https://www.terraform.io/cli/config/config-file#network_mirror)
