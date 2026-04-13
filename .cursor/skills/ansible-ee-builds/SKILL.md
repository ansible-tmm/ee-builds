---
name: ansible-ee-builds
description: >-
  Build and troubleshoot Ansible Execution Environments using ansible-builder v3.
  Use when editing execution-environment.yml, requirements.yml, requirements.txt,
  bindep.txt, ansible.cfg, or debugging EE build failures and runtime warnings.
---

# Ansible Execution Environment Builds

## ansible-builder v3 Multi-Stage Build (Critical)

`ansible-builder` v3 generates a **4-stage** Containerfile. Understanding which
stage persists into the final image is essential:

| Stage | Name | `additional_build_steps` key | Persists to final image? |
|-------|------|------------------------------|--------------------------|
| 1/4 | **base** | `prepend_base` / `append_base` | **YES** — this IS the final image's foundation |
| 2/4 | **galaxy** | `prepend_galaxy` / `append_galaxy` | **NO** — only `/usr/share/ansible` is copied out |
| 3/4 | **builder** | `prepend_builder` / `append_builder` | **NO** — only `/output/` (wheels) is copied out |
| 4/4 | **final** | `prepend_final` / `append_final` | **YES** — this is the shipped image |

### What this means in practice

- **ENV vars** set in `prepend_base` persist into the runtime image.
- **Files added** in `prepend_galaxy` (e.g. `ADD ansible.cfg`) are **discarded**
  after collection install. The final image gets the base image's original files.
- To bake a file into the final image, use `prepend_final` / `append_final`,
  NOT `prepend_galaxy`.

### Common mistake

```yaml
# WRONG — ansible.cfg is lost after stage 2
prepend_galaxy:
    - ADD _build/configs/ansible.cfg /etc/ansible/ansible.cfg

# RIGHT — ENV in prepend_base persists to runtime
prepend_base:
    - ENV ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH=ignore
```

## Base Image Selection

| Image | Python | ansible-core | Use when |
|-------|--------|-------------|----------|
| `ee-minimal-rhel9` | 3.9 | Not included | Collections don't need ansible-core >=2.17 |
| `ee-supported-rhel9` | 3.12 | 2.15.x (RPM) | Collections need newer ansible-core or you want pre-bundled collections |

- `ee-supported-rhel9` ships many collections pre-installed. Work **with** the
  base image — only add delta collections in `requirements.yml`.
- Prefer `:latest` tag over SHA pins unless reproducibility is critical.

## Working with ee-supported: Delta-Only Dependencies

The `ee-supported-rhel9` base ships collections and their Python deps pre-installed.
Overriding them causes version conflicts and runtime warnings.

### requirements.yml strategy

Only list collections **not** already in the base image:

```yaml
collections:
  - name: cisco.asa          # not in ee-supported
  - name: containers.podman  # not in ee-supported
  # Do NOT add cisco.ios, ansible.netcommon, etc. — they ship with the base
```

Check what's already installed by running:
```bash
podman run --rm <base-image> ansible-galaxy collection list
```

### requirements.txt strategy

Only list Python packages the delta collections need that aren't already
satisfied by the base image's bundled deps.

## ansible.cfg and the Galaxy Stage

The `ansible.cfg` is added in `prepend_galaxy` so that `ansible-galaxy install`
can reach Automation Hub. This file is **only used during build** — it does not
survive to the final image (see stage table above).

If you need Ansible config settings at runtime, use one of:
1. `ENV` in `prepend_base` (simplest, most reliable)
2. `ADD` in `prepend_final` or `append_final`

## pip Build Isolation

`ansible-builder >=3.1` ships pip 26+ which enforces PEP 517 build isolation.
Source-only packages (`ncclient`, `ovirt-engine-sdk-python`, `systemd-python`)
fail with `No module named 'setuptools'`.

**Workaround**: Either pin `ansible-builder==3.0.0` (avoids the issue) or set
`ENV PIP_NO_BUILD_ISOLATION=1` in `prepend_base`.

This repo pins `ansible-builder==3.0.0` in the root `requirements.txt`.

## bindep.txt for ee-supported

The base image's bundled collections have C-extension deps needing headers:

```
systemd-devel  [platform:rpm]   # systemd-python (ansible.eda)
pkgconf        [platform:rpm]   # pkg-config for C builds
libxml2-devel  [platform:rpm]   # ovirt-engine-sdk-python / lxml
libxslt-devel  [platform:rpm]   # ovirt-engine-sdk-python
python3-devel  [platform:rpm]   # any C extension
gcc            [platform:rpm]   # compiler
python3-pip    [platform:rhel-9] # microdnf can remove pip; ensure it's present
```

## CI Workflow Notes

- `generate_matrix.py` only builds EEs whose directories changed between
  `HEAD^1` and `HEAD`. Touch a file in the EE directory to force a build.
- Automation Hub 504 timeouts are transient — rerun the workflow.
- The workflow runs on merge to `main`. Use devel→main PRs.

## Debugging Checklist

When an EE build fails or produces runtime warnings:

1. **Build failure in galaxy stage?** → Check Automation Hub auth tokens, network
2. **`No module named setuptools`?** → pip build isolation issue (see above)
3. **`No module named pip`?** → Add `python3-pip` to bindep.txt + `RUN $PYCMD -m ensurepip` in prepend_base
4. **Collection version warnings at runtime?** → Check if your build overwrites the base image's ansible.cfg; use ENV var in prepend_base instead
5. **Collections pulling wrong versions?** → You're probably overriding base image collections in requirements.yml; trim to delta only
