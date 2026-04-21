# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository manages **Ansible Execution Environment (EE) container image definitions** built with `ansible-builder`. Each top-level directory (except `.github/`, `.devcontainer/`, `.vscode/`, `.ansible/`) is a self-contained EE definition. Images are built via GitHub Actions and pushed to **quay.io** (production, on push to `main`). PR builds compile the image but do not push it.

The upstream fork is `ansible-tmm/ee-builds`. This fork (`leogallego/ansible-ee-builds`) adds custom EEs.

## Build Commands

```bash
# Install ansible-builder (pinned to 3.0.0)
pip install -r requirements.txt

# Build an EE locally (from repo root)
ansible-builder build -f <ee-dir>/execution-environment.yml -t <image-name>:latest -v 3

# Build with Automation Hub token (required for certified/validated collections)
ansible-builder build -f <ee-dir>/execution-environment.yml -t <image-name>:latest -v 3 --build-arg AH_TOKEN=<token>

# Inspect what's already in a base image
podman run --rm <base-image> ansible-galaxy collection list
```

The `ansible.cfg` files use `my_ah_token` as a placeholder — CI replaces it via `sed` at build time. For local builds, either edit the placeholder or pass `--build-arg AH_TOKEN=<token>`.

## EE Directory Structure

Each EE directory follows `ansible-builder` conventions. The only required file is `execution-environment.yml`. Other files are referenced from it:

| File | Purpose |
|------|---------|
| `execution-environment.yml` | EE definition (version 3 preferred, some legacy v2) |
| `ansible-collections.yml` or `requirements.yml` | Galaxy collection dependencies |
| `python-packages.txt` or `requirements.txt` | Python pip dependencies |
| `bindep.txt` or `system-packages.txt` | System RPM packages |
| `ansible.cfg` | Galaxy server config with AH token placeholder |

Naming varies across EEs — match the convention of the specific EE you're modifying.

## ansible-builder v3 Multi-Stage Build (Critical)

`ansible-builder` v3 generates a **4-stage Containerfile**. Understanding which stages persist is essential:

| Stage | Name | Build steps key | Persists to final image? |
|-------|------|-----------------|--------------------------|
| 1 | **base** | `prepend_base` / `append_base` | **YES** — foundation of the final image |
| 2 | **galaxy** | `prepend_galaxy` / `append_galaxy` | **NO** — only `/usr/share/ansible` copied out |
| 3 | **builder** | `prepend_builder` / `append_builder` | **NO** — only `/output/` (wheels) copied out |
| 4 | **final** | `prepend_final` / `append_final` | **YES** — the shipped image |

**Key implications:**
- `ENV` vars set in `prepend_base` persist into the runtime image.
- Files added in `prepend_galaxy` (like `ansible.cfg`) are **discarded** after collection install. The final image gets the base image's original files.
- To bake a file into the final image, use `prepend_final` / `append_final`.

```yaml
# WRONG — ansible.cfg is lost after stage 2
prepend_galaxy:
    - ADD _build/configs/ansible.cfg /etc/ansible/ansible.cfg

# RIGHT — ENV in prepend_base persists to runtime
prepend_base:
    - ENV ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH=ignore
```

### Standard build steps pattern
```yaml
additional_build_steps:
  prepend_base:
    - RUN $PYCMD -m pip install --upgrade pip setuptools
  prepend_galaxy:
    - ADD _build/configs/ansible.cfg /etc/ansible/ansible.cfg
    - ARG AH_TOKEN
    - ENV ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN=$AH_TOKEN
```

The `prepend_galaxy` block injects `ansible.cfg` and the AH token so `ansible-galaxy` can pull certified/validated collections during the build. This config does NOT survive to the final image.

## Base Image Selection

Images live in `registry.redhat.io/ansible-automation-platform-<aap-version>/`:

| Image | Python | ansible-core | Use when |
|-------|--------|-------------|----------|
| `ee-minimal-rhel8/9` | 3.9 | Not included | Collections don't require ansible-core >=2.17 |
| `ee-supported-rhel8/9` | 3.12 | 2.15.x (RPM) | Collections need newer ansible-core or you want pre-bundled collections |
| `de-minimal-rhel8` | — | — | Development Environments (not EEs) |

AAP versions: `aap-23` (oldest), `aap-24` (current), `aap-25` (newest). Prefer `:latest` tag over SHA pins unless reproducibility is critical.

### Delta-only dependencies for ee-supported

`ee-supported` ships many collections and Python packages pre-installed. **Only add what's not already in the base image** — overriding bundled deps causes version conflicts and runtime warnings.

```yaml
# requirements.yml — only delta collections
collections:
  - name: cisco.asa          # not in ee-supported
  # Do NOT add cisco.ios, ansible.netcommon — they ship with the base
```

## pip Build Isolation

`ansible-builder >=3.1` ships pip 26+ which enforces PEP 517 build isolation. Source-only packages (`ncclient`, `ovirt-engine-sdk-python`, `systemd-python`) fail with `No module named 'setuptools'`. This repo pins `ansible-builder==3.0.0` to avoid the issue. Don't upgrade without addressing build isolation.

## CI/CD Architecture

### Workflows (`.github/workflows/`)

- **`push-ee-build.yml`** — Triggers on push to `main`. Detects changed EE directories via `generate_matrix.py`, builds in parallel, pushes to quay.io with tags `latest` and `{SHA}`. Environment: `deploy`.
- **`pr-ee-build.yml`** — Triggers on PRs to `main` (`pull_request_target`). Same matrix detection. Builds locally but does **not** push to any registry. Posts a PR comment with installed collections and Ansible version. Environment: `test`.
- **`generate_matrix.py`** — Compares git refs to find changed directories containing `execution-environment.yml`, outputs a JSON matrix.
- **`refresh-ah-token.yml`** / **`refresh-token.yml`** — Scheduled (1st and 26th of month) token refresh against Red Hat SSO.

### Required secrets
- `AH_TOKEN` — Red Hat Automation Hub offline token
- `REDHAT_SA_USERNAME` / `REDHAT_SA_PASSWORD` — registry.redhat.io service account
- `REDHAT_USERNAME` / `REDHAT_PASSWORD` — quay.io credentials
- `QUAY_USER` — quay.io org/user namespace

### How CI detects what to build
Only EE directories with changed files between the base and head refs are built. No workflow changes needed when adding a new EE — `generate_matrix.py` auto-detects directories with `execution-environment.yml`. Touch a file in an EE directory to force a rebuild. Automation Hub 504 timeouts are transient — just rerun the workflow.

## Adding a New EE

1. Create a new directory at the repo root (name = image name, use lowercase with hyphens or underscores).
2. Add `execution-environment.yml` (version 3) pointing to the desired base image.
3. Add dependency files as needed (`requirements.yml`, `requirements.txt`/`python-packages.txt`, `bindep.txt`).
4. Copy `ansible.cfg` from an existing EE (contains Galaxy server config with `my_ah_token` placeholder).
5. Add `ansible.cfg` to `additional_build_files` in the EE definition.
6. No workflow changes needed.

## Debugging EE Builds

| Symptom | Cause | Fix |
|---------|-------|-----|
| Build failure in galaxy stage | Automation Hub auth | Check AH_TOKEN, network connectivity |
| `No module named setuptools` | pip build isolation (ansible-builder >=3.1) | Stay on `ansible-builder==3.0.0` or set `ENV PIP_NO_BUILD_ISOLATION=1` in `prepend_base` |
| `No module named pip` | microdnf removed pip | Add `python3-pip` to `bindep.txt` + `RUN $PYCMD -m ensurepip` in `prepend_base` |
| Collection version warnings at runtime | Build overwrites base image's ansible.cfg | Use `ENV ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH=ignore` in `prepend_base` (not ansible.cfg in galaxy stage) |
| Collections pulling wrong versions | Overriding base image collections | Trim `requirements.yml` to delta-only |
