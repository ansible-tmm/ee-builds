---
description: Comprehensive symptom-cause-fix table for debugging EE build failures
globs: "**/execution-environment.yml,**/bindep.txt,**/requirements.txt,**/python-packages.txt"
alwaysApply: false
---

# Debugging EE Builds

## Symptom / Cause / Fix Reference

| Symptom | Cause | Fix | Rule |
|---------|-------|-----|------|
| `fatal error: Python.h: No such file or directory` | Missing python-devel or wrong version in bindep.txt | Add `python3.12-devel` (must match active Python) to bindep.txt | 01-B |
| `ModuleNotFoundError: No module named 'requirements'` in builder introspect step | PYCMD overridden to 3.12 but builder scripts only installed for 3.9 (AAP 2.7) | Add `RUN $PYCMD -m pip install ... requirements-parser bindep pyyaml distro packaging Parsley` in prepend_builder | 01-C |
| `ModuleNotFoundError: No module named 'setuptools'` during pip install | pip 24+ enforces PEP 517 build isolation; source-only package needs setuptools | Pin `pip<24`, set `ENV PIP_NO_BUILD_ISOLATION=1`, or don't upgrade pip | 02 |
| `No module named 'ansible'` in check_ansible step | Final image `/usr/bin/python3` points to 3.9 but ansible installed under 3.12 | Set `ENV PYCMD=/usr/bin/python3.12` in prepend_final | 01-A |
| Wheels downloaded as `cp39` instead of `cp312` | PYCMD hijacked to Python 3.9 by microdnf | Set `ENV PYCMD=/usr/bin/python3.12` in prepend_builder and prepend_final | 01-A |
| `error: command 'gcc' failed` | gcc not installed in builder | Add `gcc [compile platform:rhel-9]` to bindep.txt | 01-B |
| `No package matches 'python39-devel'` | Wrong python-devel package name for the RHEL version | Use `python3.12-devel` for RHEL 9, `python3.11-devel` for RHEL 8 AAP 2.5 | 01-B |
| Galaxy stage fails with 401/403 | AH_TOKEN missing or expired | Check `--build-arg AH_TOKEN=...`, verify token is fresh, check ansible.cfg server config | CI |
| Galaxy stage fails with 504 | Automation Hub transient error | Rerun the workflow | CI |
| Galaxy warnings: `Skipping Galaxy server ... HTTP Error 400` | Validated content server token not set in prepend_galaxy | Add `ENV ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_VALIDATED_TOKEN=$AH_TOKEN` alongside the published token. Non-fatal if collections install from fallback servers, but slows the build and may miss validated-only content | 07 |
| Collection version warnings at runtime | ee-supported base collections declare higher ansible-core than shipped | `ENV ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH=ignore` in prepend_base | 05 |
| SSH to device fails with `kex_exchange_identification` | RHEL 9 crypto policies reject legacy algorithms | Use `update-crypto-policies --set DEFAULT:SHA1` or surgical config replacement in append_final | 05 |
| `ansible.cfg` changes missing at runtime | ansible.cfg added only in galaxy stage (discarded after collection install) | Also ADD ansible.cfg in `append_final` if runtime config is needed | 03 |
| `No module named pip` in base stage | Base image does not ship pip | Install via `microdnf install -y python3-pip` or `RUN $PYCMD -m ensurepip` in prepend_base | 01 |
| pip installing into wrong Python / wrong site-packages | `/usr/bin/python3` hijacked to 3.9 | Always use `$PYCMD -m pip install` with PYCMD override, never bare `pip install` | 01-A |

| `No package matches 'openshift-clients'` | `kubernetes.core` collection declares `openshift-clients` in its bindep.txt, which is not available in standard UBI repos | Use `dependencies.exclude.system: [openshift-clients]` in execution-environment.yml (requires ansible-builder 3.1+), or add `openshift-clients` RPM manually via `additional_build_steps` if actually needed | 05 |

## Quick Diagnostic Steps

1. **Check which Python the image uses**: `podman run --rm <image> python3 --version`
2. **Check where python3 points**: `podman run --rm <image> ls -la /usr/bin/python3*`
3. **Check installed collections**: `podman run --rm <image> ansible-galaxy collection list`
4. **Check ansible version**: `podman run --rm <image> ansible --version`
5. **Check pip packages**: `podman run --rm <image> python3 -m pip list`
6. **Build with maximum verbosity**: `ansible-builder build -v 3 ...`
