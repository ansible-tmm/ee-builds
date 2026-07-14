---
description: Common workarounds — legacy crypto on RHEL 9, PIP_IGNORE_INSTALLED, collection version mismatch suppression
globs: "**/execution-environment.yml,**/bindep.txt"
alwaysApply: false
---

# Common Workarounds

## Legacy Crypto on RHEL 9

RHEL 9 default crypto policies disable SHA-1, DSA, and weak DH groups. SSH to older network devices (IOS-XE, NX-OS, JunOS, older Linux hosts) fails with errors like `kex_exchange_identification` or `no matching host key type found`.

### Approach 1: update-crypto-policies (system-wide)

```yaml
append_final:
    - RUN microdnf install -y crypto-policies-scripts && update-crypto-policies --set DEFAULT:SHA1 && microdnf clean all
```

Pro: Official Red Hat method, one line.
Con: Weakens all crypto system-wide in the container.

Reference: `network-ee`.

### Approach 2: Surgical config replacement (targeted)

```yaml
additional_build_files:
    - src: crypto-policies/libssh-legacy.config
      dest: configs
    - src: crypto-policies/opensslcnf-legacy.config
      dest: configs

additional_build_steps:
    prepend_final:
        - ADD _build/configs/libssh-legacy.config /etc/crypto-policies/back-ends/libssh.config
        - ADD _build/configs/opensslcnf-legacy.config /etc/crypto-policies/back-ends/opensslcnf.config
```

Pro: Only affects SSH/TLS backends, leaves rest of crypto policy intact.
Con: Requires maintaining the config files in the EE directory.

Reference: `netbox-summit-2026-ee-legacy-crypto`, `netbox-webinar-legacy-crypto-ee`.

### SSH-specific ENV

For libssh RSA key support without changing crypto policies:

```yaml
prepend_base:
    - ENV ANSIBLE_LIBSSH_PUBLICKEY_ALGORITHMS=ssh-rsa
```

Reference: `network-ee`.

## Collection System Dependencies Not Available in UBI

Some collections declare system packages in their `bindep.txt` that are not available in standard UBI repositories. The most common example is `kubernetes.core` which requires `openshift-clients`, an RPM only available with an OpenShift subscription.

### Fix: Exclude the system dependency (ansible-builder 3.1+)

```yaml
dependencies:
  galaxy: requirements.yml
  python: requirements.txt
  system: bindep.txt
  exclude:
    system:
      - openshift-clients
```

This tells ansible-builder to skip `openshift-clients` from the collection's introspected bindep. The core `k8s`, `k8s_info`, `helm` modules work fine without it (they use the Python `kubernetes` client). Only the `kubectl` connection plugin and `kustomize` lookup actually need the binary.

If you do need the binary, you have two options:

Option A: Enable the OpenShift repo via PKGMGR_OPTS (for hosts with subscription-manager):
```yaml
prepend_builder:
    - ENV PKGMGR_OPTS="--nodocs --setopt=install_weak_deps=0 --setopt=rhocp-4.16-for-rhel-9-x86_64-rpms.enabled=true"
prepend_final:
    - ENV PKGMGR_OPTS="--nodocs --setopt=install_weak_deps=0 --setopt=rhocp-4.16-for-rhel-9-x86_64-rpms.enabled=true"
```
Must be set in both builder and final stages. Adjust the repo name for your RHEL and OCP versions.

Option B: Bundle the RPM directly (for RHUI/cloud environments without the OCP repo):
```yaml
additional_build_files:
    - src: openshift-clients-4.16.x.rpm
      dest: rpms
additional_build_steps:
    prepend_base:
        - COPY _build/rpms/*.rpm /tmp/openshift-clients.rpm
        - RUN rpm -ivh /tmp/openshift-clients.rpm
```

Reference: [Red Hat Solution 7024259](https://access.redhat.com/solutions/7024259), `product-demos-ee`.

Reference: [kubernetes.core#1141](https://github.com/ansible-collections/kubernetes.core/issues/1141)

## PIP_IGNORE_INSTALLED

When pip encounters a package already installed by the base image's RPM, it may refuse to upgrade or get confused by dist-info ownership conflicts.

```yaml
prepend_base:
    - ENV PIP_IGNORE_INSTALLED=1
```

This tells pip to ignore already-installed packages and install fresh copies. Use only when RPM-installed packages conflict with pip version requirements.

Tradeoff: increases image size due to duplicate packages.

Reference: `netbox-for-nuno`, `netbox-summit-2026-ee`, `network-netbox-eda-ee`.

## Collection Version Mismatch Suppression

ee-supported images bundle collections that may declare `requires_ansible: ">=2.17"` but ship ansible-core 2.15 or 2.16. This produces noisy runtime warnings.

```yaml
prepend_base:
    - ENV ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH=ignore
```

Put this in `prepend_base` (not in ansible.cfg in the galaxy stage, which would be discarded).

Reference: `network-ee`.
