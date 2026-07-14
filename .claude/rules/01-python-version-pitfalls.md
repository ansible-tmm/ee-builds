---
description: Python version pitfalls in RHEL 9 EE builds — PYCMD hijack, python-devel matching, builder dependency reinstall
globs: "**/execution-environment.yml,**/bindep.txt"
alwaysApply: false
---

# Python Version Pitfalls

## A. PYCMD Hijack on RHEL 9

On RHEL 9 ee-minimal images, the base image ships Python 3.12 at `/usr/bin/python3.12` with `/usr/bin/python3` symlinked to it. When `microdnf` installs system packages (from bindep.txt or build steps), it pulls in `python3-3.9` as a transitive dependency. The `python3-3.9` RPM takes ownership of `/usr/bin/python3`, so `$PYCMD` resolves to Python 3.9 instead of 3.12.

This causes: wrong wheels downloaded (cp39 instead of cp312), C extensions compiled against wrong headers, and packages installed into the wrong site-packages.

**Affected**: AAP 2.6 ee-minimal-rhel9, AAP 2.7 ee-minimal-rhel9 (any RHEL 9 ee-minimal).
**Not affected**: RHEL 8 images, ee-supported images.

### DO

```yaml
# Pin PYCMD in BOTH builder and final stages
prepend_builder:
    - ENV PYCMD=/usr/bin/python3.12
prepend_final:
    - ENV PYCMD=/usr/bin/python3.12
```

Reference: `netbox-for-nuno`, `netbox-summit-2026-ee`, `aws_gameday_ee`.

### DON'T

```yaml
# No PYCMD override — microdnf will hijack /usr/bin/python3 to 3.9
prepend_builder: []
```

```yaml
# Setting PYCMD only in builder — final image still has wrong Python
prepend_builder:
    - ENV PYCMD=/usr/bin/python3.12
# Missing prepend_final!
```

## B. python-devel Must Match the Active Python

The `python3.XX-devel` package in bindep.txt provides C header files (`Python.h`) for compilation. It MUST match the Python version the builder compiles C extensions with (i.e., what `$PYCMD` resolves to after applying the PYCMD fix).

| Base Image | Python | Correct devel package |
|-----------|--------|----------------------|
| AAP 2.6/2.7 ee-minimal-rhel9 | 3.12 | `python3.12-devel` |
| AAP 2.5 ee-minimal-rhel8 | 3.11 | `python3.11-devel` |
| AAP 2.4 ee-minimal-rhel8 | 3.12 | `python3.12-devel` |

### DO

```
python3.12-devel [compile platform:rhel-9]
```

### DON'T

```
# WRONG: Headers for 3.11 but builder compiles with 3.12
python3.11-devel [compile platform:rhel-9]

# WRONG: Generic python3-devel may resolve to 3.9 headers after hijack
python3-devel [compile platform:rhel-9]
```

## C. Builder Script Dependencies Reinstall (AAP 2.7 Only)

When you override `PYCMD=/usr/bin/python3.12` in `prepend_builder`, the builder's introspection scripts (`introspect.py`) run under Python 3.12. But the builder image installed their dependencies (`requirements-parser`, `bindep`, `pyyaml`, etc.) for the default Python 3.9. The introspect step fails with `ModuleNotFoundError: No module named 'requirements'`.

This is needed for AAP 2.7. AAP 2.6 builder images handle this differently and do NOT need the reinstall.

### DO (AAP 2.7)

```yaml
prepend_builder:
    - ENV PYCMD=/usr/bin/python3.12
    - RUN $PYCMD -m pip install --upgrade pip setuptools requirements-parser bindep pyyaml distro packaging Parsley
prepend_final:
    - ENV PYCMD=/usr/bin/python3.12
```

Reference: `aws_gameday_ee`.

### DON'T (AAP 2.7)

```yaml
# Sets PYCMD but doesn't reinstall builder deps — introspect scripts fail
prepend_builder:
    - ENV PYCMD=/usr/bin/python3.12
```
