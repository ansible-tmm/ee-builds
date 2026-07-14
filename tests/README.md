# Test Execution Environments

Regression tests for known EE build pitfalls documented in `.claude/rules/`.

## Test Matrix

| Test EE | Base Image | Rules Tested | Pitfall Validated |
|---------|-----------|-------------|-------------------|
| `test-ee-aap27-minimal` | AAP 2.7 ee-minimal-rhel9 | 01 (A, B, C) | PYCMD hijack + builder deps reinstall + python3.12-devel + C extension |
| `test-ee-aap26-minimal` | AAP 2.6 ee-minimal-rhel9 | 01 (A) | PYCMD hijack without builder deps reinstall |
| `test-ee-aap26-supported` | AAP 2.6 ee-supported-rhel9 | 04, 05 | Delta-only collections, version mismatch suppression |
| `test-ee-source-only-pkg` | AAP 2.6 ee-minimal-rhel9 | 02 | pip<24 pin prevents build isolation failure with systemd-python |

## Running Locally

```bash
# From repo root
ansible-builder build \
  -f tests/<test-dir>/execution-environment.yml \
  -t test:latest -v 3 \
  --build-arg AH_TOKEN=<your-token>
```

## CI

These test EEs are built on every PR via `.github/workflows/test-ee-build.yml`. All four test EEs build on every PR regardless of which files changed, serving as regression tests for the documented rules.
