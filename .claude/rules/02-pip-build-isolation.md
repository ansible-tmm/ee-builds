---
description: pip build isolation traps — pip upgrade breaks source-only packages, PIP_NO_BUILD_ISOLATION, pip pinning
globs: "**/execution-environment.yml,**/requirements.txt,**/python-packages.txt"
alwaysApply: false
---

# pip Build Isolation

## The pip Upgrade Trap

`ansible-builder` calls `ensurepip` which keeps the base image's pip (23.x). Build isolation is lax at pip <24.

When an EE's `prepend_base` runs `RUN $PYCMD -m pip install --upgrade pip`, pip upgrades to 24+ which enforces PEP 517 build isolation by default. Source-only packages then fail because the isolated build environment lacks `setuptools`.

## Affected Packages

These Python packages have no pre-built wheel on PyPI and require compilation from source:

- `systemd-python`: needs `setuptools`, `systemd-devel`, `gcc`
- `ovirt-engine-sdk-python`: needs `setuptools`, `libxml2-devel`, `libxslt-devel`, `gcc`
- `ncclient`: previously source-only, now ships a universal wheel (no longer affected)

## Fixes (Choose One)

### Option 1: Pin pip below 24 (recommended when you need pip features)

```yaml
prepend_base:
    - RUN $PYCMD -m pip install 'pip<24' setuptools
```

### Option 2: Disable build isolation

```yaml
prepend_base:
    - ENV PIP_NO_BUILD_ISOLATION=1
    - RUN $PYCMD -m pip install --upgrade pip setuptools
```

pip will use the system `setuptools` instead of creating an isolated environment.

### Option 3: Do not upgrade pip (safest)

```yaml
prepend_base: []
```

Rely on the base image's pip. This is the simplest approach and avoids the problem entirely.

Reference: `network-ee` uses `ensurepip` only (no upgrade) specifically because it installs `ovirt-engine-sdk-python`.

## DON'T

```yaml
# Upgrades to pip 24+ — source-only packages will fail
prepend_base:
    - RUN $PYCMD -m pip install --upgrade pip setuptools
```

This pattern exists in many EEs in the repo. It works only because those EEs do not install source-only packages. Adding `systemd-python` or `ovirt-engine-sdk-python` to their requirements.txt will break the build.
