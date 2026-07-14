---
description: Checklist for adding a new EE definition — covers all known pitfalls in sequence
globs: "**/execution-environment.yml"
alwaysApply: false
---

# Adding a New EE

## Checklist

1. **Choose base image** (see rule 04)
   - ee-minimal or ee-supported?
   - AAP version (24, 25, 26, 27)?
   - RHEL version (rhel8, rhel9)?

2. **Check Python version** of chosen base image
   ```bash
   podman run --rm <base-image> python3 --version
   ```

3. **If RHEL 9 ee-minimal**: add PYCMD override (see rule 01-A)
   ```yaml
   prepend_builder:
       - ENV PYCMD=/usr/bin/python3.12
   prepend_final:
       - ENV PYCMD=/usr/bin/python3.12
   ```

4. **If AAP 2.7**: also reinstall builder script dependencies (see rule 01-C)
   ```yaml
   prepend_builder:
       - ENV PYCMD=/usr/bin/python3.12
       - RUN $PYCMD -m pip install --upgrade pip setuptools requirements-parser bindep pyyaml distro packaging Parsley
   ```

5. **Set correct python-devel in bindep.txt** (see rule 01-B)
   - Must match the Python your PYCMD resolves to
   - AAP 2.6/2.7 rhel9: `python3.12-devel [compile platform:rhel-9]`
   - AAP 2.5 rhel8: `python3.11-devel [compile platform:rhel-8]`

6. **If using source-only packages** (systemd-python, ovirt-engine-sdk-python): do NOT upgrade pip, or use PIP_NO_BUILD_ISOLATION (see rule 02)

7. **If using ee-supported base**: only add delta collections and packages not already in the base image (see rule 04)

8. **Add ansible.cfg** to `additional_build_files` and inject in `prepend_galaxy`. Set the token for BOTH published and validated servers, otherwise collections from the validated content repo will fail with HTTP 400.
   ```yaml
   additional_build_files:
       - src: ansible.cfg
         dest: configs
   additional_build_steps:
       prepend_galaxy:
           - ADD _build/configs/ansible.cfg /etc/ansible/ansible.cfg
           - ARG AH_TOKEN
           - ENV ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN=$AH_TOKEN
           - ENV ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_VALIDATED_TOKEN=$AH_TOKEN
   ```

9. **If ansible.cfg needed at runtime**: also ADD in `append_final` (see rule 03). The galaxy stage copy is discarded.

10. **If targeting legacy network devices on RHEL 9**: add crypto policy workaround in `append_final` (see rule 05)

11. **Set package_manager_path**
    ```yaml
    options:
        package_manager_path: /usr/bin/microdnf
    ```

12. **Use version: 3** for the execution-environment.yml format. Version 1 and 2 are legacy.

13. **Test locally**
    ```bash
    ansible-builder build -f <dir>/execution-environment.yml -t test:latest -v 3 --build-arg AH_TOKEN=<token>
    ```

14. **No CI changes needed**: `generate_matrix.py` auto-detects new directories with `execution-environment.yml`.

## Directory Structure

```
my-new-ee/
  execution-environment.yml    # Required
  requirements.yml             # Galaxy collections
  requirements.txt             # Python pip packages
  bindep.txt                   # System RPM packages
  ansible.cfg                  # Galaxy server config (copy from existing EE)
```

File naming varies across EEs (`ansible-collections.yml` vs `requirements.yml`, `python-packages.txt` vs `requirements.txt`). Match the convention of similar EEs or use the names above.
