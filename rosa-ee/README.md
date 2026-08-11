# rosa-ee

Ansible Execution Environment for **ROSA (Red Hat OpenShift Service on AWS) lifecycle demos** — create and destroy clusters only.

**Image**: `quay.io/acme_corp/rosa-ee:latest`

## What's Included

| Tool | Purpose |
|------|---------|
| `rosa` CLI | Create, describe, and delete ROSA clusters |
| `aws` CLI v2 | AWS authentication and resource queries |
| `oc` client | OpenShift cluster interaction (optional convenience) |
| `jq` | JSON parsing in shell tasks |
| `amazon.aws` collection | Ansible modules for AWS |
| `community.aws` collection | Extended AWS modules |
| `ansible.controller` collection | AAP job template management |

## Build

### Prerequisites

- `ansible-builder==3.0.0` (pinned in repo root `requirements.txt`)
- Access to `registry.redhat.io` (Red Hat subscription)
- Automation Hub token (for certified collections)

### Build locally

```bash
cd rosa-ee

# Set your Automation Hub token
export AH_TOKEN=<your-token>

ansible-builder build \
  --tag quay.io/acme_corp/rosa-ee:latest \
  --build-arg AH_TOKEN=$AH_TOKEN
```

### Push to Quay

```bash
podman login quay.io
podman push quay.io/acme_corp/rosa-ee:latest
```

### Tag with date

```bash
podman tag quay.io/acme_corp/rosa-ee:latest quay.io/acme_corp/rosa-ee:$(date +%Y%m%d)
podman push quay.io/acme_corp/rosa-ee:$(date +%Y%m%d)
```

## Smoke Test

```bash
podman run --rm quay.io/acme_corp/rosa-ee:latest rosa version
podman run --rm quay.io/acme_corp/rosa-ee:latest aws --version
podman run --rm quay.io/acme_corp/rosa-ee:latest jq --version
podman run --rm quay.io/acme_corp/rosa-ee:latest oc version --client
```

## Required Credentials (Runtime)

These are **never** baked into the image. Pass them as environment variables or AAP credentials at runtime.

| Variable | Purpose |
|----------|---------|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret key |
| `AWS_DEFAULT_REGION` | AWS region (e.g. `us-east-2`) |
| `ROSA_TOKEN` | OCM token from https://console.redhat.com/openshift/token |

## AAP Controller Setup

1. **Add Execution Environment**:
   - Name: `ROSA Lifecycle EE`
   - Image: `quay.io/acme_corp/rosa-ee:latest`
   - Pull: `Always`

2. **Create Credential Types** (if not already present):
   - **AWS**: Use built-in `Amazon Web Services` credential type
   - **ROSA Token**: Custom credential type with `ROSA_TOKEN` injected as env var

3. **Create Job Template**:
   - Execution Environment: `ROSA Lifecycle EE`
   - Credentials: AWS + ROSA Token
   - Extra vars or survey for cluster name, region, etc.

## ROSA Lifecycle Commands (Reference)

```bash
# Login
rosa login --token=$ROSA_TOKEN

# Create cluster (single-AZ, minimal for demo)
rosa create cluster --cluster-name=demo-cluster \
  --region=us-east-2 \
  --replicas=2 \
  --machine-pool-min-replicas=2 \
  --sts --mode=auto --yes

# Watch status
rosa describe cluster --cluster=demo-cluster
rosa logs install --cluster=demo-cluster --watch

# Delete cluster
rosa delete cluster --cluster=demo-cluster --yes
rosa logs uninstall --cluster=demo-cluster --watch

# Cleanup STS roles after delete
rosa delete operator-roles -c <cluster-id> --yes
rosa delete oidc-provider -c <cluster-id> --yes
```

## Scope

This EE is intentionally minimal — **create and destroy only**. It does not include:
- Application deployment tooling
- Operator management
- GitOps/ArgoCD integration

For app lifecycle, use a separate EE with the full OpenShift collection stack.
