# network-ee

Custom Ansible Execution Environment for the [Network Automation Workshop](https://github.com/rhpds/zt-network-automation-workshop).

**Image**: `quay.io/acme_corp/network-ee:latest`

## Base Image

Built on `registry.redhat.io/ansible-automation-platform-26/ee-supported-rhel9:latest`, which ships:
- Python 3.9, ansible-core 2.15.x (RPM)
- Pre-bundled collections: `cisco.ios`, `arista.eos`, `junipernetworks.junos`, `ansible.netcommon`, `ansible.utils`, `ansible.controller`, `ansible.platform`, and more

This EE adds only **delta** collections and packages not already in the base image.

## Build

Builds are triggered automatically by GitHub Actions on merge to `main`. To build locally:

```bash
pip install ansible-builder==3.0.0
cd network-ee
ansible-builder build --tag quay.io/acme_corp/network-ee:latest
```

> **Note**: `ansible-builder==3.0.0` is required. Newer versions change pip build isolation behavior and break source-only packages.

## Key Build Details

### ansible-builder v3 Multi-Stage Build

`ansible-builder` v3 generates a 4-stage Containerfile. Only stages 1 (base) and 4 (final) persist into the runtime image. Files added in stage 2 (galaxy) — including `ansible.cfg` — are discarded after collection install. This is why:

- **ENV vars** are set in `prepend_base` (stage 1) for runtime config
- **`ansible.cfg`** is added in both `prepend_galaxy` (for build-time galaxy access) and `append_final` (for runtime)

### Delta-Only Collections

`requirements.yml` only lists collections **not** already in the base image. Do not add collections the base image ships (e.g. `cisco.ios`, `ansible.netcommon`) — overriding them causes version conflicts.

### RHEL 9 ssh-rsa Crypto Policy (Temporary Workaround)

RHEL 9's system crypto policy blocks `ssh-rsa` at the OS libssh C library level. The workshop's Cisco IOS lab routers require `ssh-rsa` for SSH authentication. Without the workaround, connections fail with:

```
ssh connection failed: Failed to authenticate public key: The key algorithm 'ssh-rsa'
is not allowed to be used by PUBLICKEY_ACCEPTED_TYPES configuration option
```

This cannot be fixed with Ansible config alone (`ansible.cfg`, environment variables, or host vars) — the OS-level libssh library rejects the algorithm before Ansible is consulted.

**Current fix** in `execution-environment.yml`:

```yaml
append_final:
    - RUN microdnf install -y crypto-policies-scripts && update-crypto-policies --set DEFAULT:SHA1 && microdnf clean all
```

#### When to remove this workaround

Remove the `update-crypto-policies` line and the `ANSIBLE_LIBSSH_PUBLICKEY_ALGORITHMS` ENV var once the lab router images are upgraded to support modern key exchange algorithms (e.g. `ecdsa-sha2-nistp256`, `ssh-ed25519`). To remove:

1. Delete from `execution-environment.yml`:
   - The `update-crypto-policies` line in `append_final`
   - The `ENV ANSIBLE_LIBSSH_PUBLICKEY_ALGORITHMS=ssh-rsa` line in `prepend_base`
2. Optionally remove the `[libssh_connection]` section from `ansible.cfg`
3. Rebuild and test against the lab routers

## Files

| File | Purpose |
|------|---------|
| `execution-environment.yml` | ansible-builder v3 build definition |
| `requirements.yml` | Delta Ansible collections (not in base image) |
| `requirements.txt` | Delta Python packages (not in base image) |
| `bindep.txt` | System packages for C extension compilation |
| `ansible.cfg` | Galaxy server URLs (build-time) + runtime config |
