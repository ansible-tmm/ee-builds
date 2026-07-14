---
description: Base image selection guide — AAP/RHEL/Python version matrix, ee-minimal vs ee-supported, delta dependencies
globs: "**/execution-environment.yml,**/requirements.yml,**/ansible-collections.yml"
alwaysApply: false
---

# Base Image Selection

## Image Naming Convention

```
registry.redhat.io/ansible-automation-platform-{AAP_VERSION}/{IMAGE_TYPE}-{RHEL_VERSION}:{TAG}
```

- AAP versions: 24, 25, 26, 27
- Image types: `ee-minimal`, `ee-supported`, `de-minimal` (EDA Decision Environments), `de-supported` (EDA Decision Environments)
- RHEL versions: `rhel8`, `rhel9`
- Tags: `:latest` or pinned (e.g., `:2.16-1781093888`)

## Python Version by Base Image

| AAP | RHEL | ee-minimal Python | ee-supported Python |
|-----|------|-------------------|---------------------|
| 24 | rhel8 | 3.12 | 3.9 |
| 24 | rhel9 | 3.12 | 3.12 |
| 25 | rhel8 | 3.12 | 3.11 |
| 25 | rhel9 | 3.12 | 3.12 |
| 26 | rhel9 | 3.12 | 3.12 |
| 27 | rhel9 | 3.12 | 3.12 |

This table determines which `python3.XX-devel` package to use in bindep.txt (see rule 01).

## ee-minimal vs ee-supported

**Use ee-minimal when:**
- You want full control over which collections are installed
- You want the smallest possible image size
- You are building a purpose-specific EE (e.g., AWS-only, ServiceNow-only)

**Use ee-supported when:**
- You need pre-bundled Red Hat certified collections (network, cloud, etc.)
- You only need to add a few extra collections on top
- You want the collections Red Hat supports and tests together

## Delta-Only Dependencies for ee-supported

ee-supported ships many collections and Python packages pre-installed. Only add what is NOT already in the base image. Overriding bundled deps causes version conflicts and runtime warnings.

### DO

```yaml
collections:
  - name: cisco.asa           # NOT in ee-supported base
  - name: servicenow.itsm     # NOT in ee-supported base
```

### DON'T

```yaml
collections:
  - name: cisco.ios            # Already in ee-supported!
  - name: ansible.netcommon    # Already in ee-supported!
  - name: ansible.utils        # Already in ee-supported!
```

To check what's in a base image:

```bash
podman run --rm <base-image> ansible-galaxy collection list
podman run --rm <base-image> pip list
```

## RHEL 9 Considerations

When using any RHEL 9 ee-minimal image:

1. The PYCMD hijack applies (see rule 01). Always set `ENV PYCMD=/usr/bin/python3.12` in prepend_builder and prepend_final.
2. Default crypto policies may break SSH to older devices (see rule 05).
3. Use `python3.12-devel` (not `python3-devel` or `python3.11-devel`) in bindep.txt.

## Tag Pinning

- Use `:latest` for most EEs (gets security updates automatically)
- Pin to a specific tag (e.g., `:2.16-1781093888`) only when build reproducibility is critical
- Example of pinned: `aws_gameday_ee`
- Example of latest: `netbox-summit-2026-ee`
