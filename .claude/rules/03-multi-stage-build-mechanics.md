---
description: ansible-builder v3 multi-stage build — what persists, ENV placement, file placement across 4 stages
globs: "**/execution-environment.yml"
alwaysApply: false
---

# Multi-Stage Build Mechanics

## Stage Persistence

`ansible-builder` v3 generates a 4-stage Containerfile:

| Stage | Build Steps Key | What Survives | What Is Discarded |
|-------|----------------|---------------|-------------------|
| 1. base | `prepend_base` / `append_base` | Everything (foundation of final image) | Nothing |
| 2. galaxy | `prepend_galaxy` / `append_galaxy` | Only `/usr/share/ansible` (collections) | All other files, ENV vars, installed packages |
| 3. builder | `prepend_builder` / `append_builder` | Only `/output/` (compiled wheels) | All other files, ENV vars, system packages |
| 4. final | `prepend_final` / `append_final` | Everything (this IS the shipped image) | Nothing |

## Common Mistakes

### ansible.cfg in galaxy stage does NOT persist

```yaml
# WRONG: ansible.cfg is lost after galaxy stage completes
prepend_galaxy:
    - ADD _build/configs/ansible.cfg /etc/ansible/ansible.cfg
# The final image gets the BASE IMAGE's original ansible.cfg
```

The galaxy stage ansible.cfg is correct for collection installation (it needs the AH token). But if you also need ansible.cfg at runtime, add it separately in the final stage:

```yaml
append_final:
    - ADD _build/configs/ansible.cfg /etc/ansible/ansible.cfg
```

Reference: `network-ee` does this correctly.

### ENV placement matters

- `ENV` in `prepend_base`: persists to the final image (good for runtime config)
- `ENV` in `prepend_galaxy`: discarded after collection install
- `ENV` in `prepend_builder`: discarded after wheel compilation
- `ENV` in `prepend_final`: persists to the final image

```yaml
# CORRECT: Runtime ENV in prepend_base persists everywhere
prepend_base:
    - ENV ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH=ignore

# CORRECT: AH_TOKEN only needed during galaxy stage
prepend_galaxy:
    - ARG AH_TOKEN
    - ENV ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN=$AH_TOKEN
```

### PYCMD must be set in BOTH builder and final

Setting `ENV PYCMD` only in `prepend_builder` fixes the build compilation, but the final image still has the wrong PYCMD. Both stages need it:

```yaml
prepend_builder:
    - ENV PYCMD=/usr/bin/python3.12
prepend_final:
    - ENV PYCMD=/usr/bin/python3.12
```

### ARG vs ENV

- Use `ARG` for build-time secrets (like `AH_TOKEN`) that should NOT persist in the image
- Use `ENV` for configuration that needs to persist at runtime
- `ARG` values are available only in the stage where they are declared
