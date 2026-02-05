# Teleport SSH EE - Verification & Troubleshooting Guide

## Quick Verification Checklist

### ✅ Pre-flight Check (Before Running Jobs)

```bash
# 1. Verify tbot service is running
sudo systemctl status tbot-sean-test.service

# 2. Check if certificates exist and are recent (should refresh every ~15min)
ls -lh /var/lib/teleport-bot/sean-test.teleport.sh/out/
stat /var/lib/teleport-bot/sean-test.teleport.sh/out/key-cert.pub

# 3. Inspect certificate details (validity period, principals, etc.)
ssh-keygen -L -f /var/lib/teleport-bot/sean-test.teleport.sh/out/key-cert.pub

# 4. Test SSH manually (outside container)
ssh -F /var/lib/teleport-bot/sean-test.teleport.sh/out/sean-test.teleport.sh.ssh_config \
  ec2-user@<target-host>.sean-test.teleport.sh hostname

# 5. Verify SELinux context (if applicable)
ls -Z /var/lib/teleport-bot/sean-test.teleport.sh/out/
```

**Expected output for certificate inspection:**
```
Type: ssh-rsa-cert-v01@openssh.com user certificate
Public key: RSA-CERT SHA256:...
Signing CA: RSA SHA256:...
Key ID: "bot-ansible-aap-bot"
Serial: 0
Valid: from 2024-02-04T10:30:00 to 2024-02-04T11:30:00
Principals:
        ec2-user
        ubuntu
Extensions:
        permit-port-forwarding
        permit-pty
```

### ✅ Container-Level Check

```bash
# Test the EE locally with bind mount
podman run -it --rm \
  -v /var/lib/teleport-bot/sean-test.teleport.sh/out:/teleport-bot:ro \
  quay.io/<your-org>/teleport-ssh-ee:latest \
  /bin/bash

# Inside container, run these commands:
ls -la /teleport-bot/
cat /teleport-bot/sean-test.teleport.sh.ssh_config
tbot version  # Should show Teleport version
ssh -V        # Should show OpenSSH version

# Test SSH from inside container
ssh -F /teleport-bot/sean-test.teleport.sh.ssh_config \
  ec2-user@<target-host>.sean-test.teleport.sh hostname

# Test Ansible ping
ansible all -i "<target-host>.sean-test.teleport.sh," -u ec2-user -m ping \
  --ssh-extra-args="-F /teleport-bot/sean-test.teleport.sh.ssh_config"
```

### ✅ AAP Job Check

After launching a job in AAP:

1. **Check job output** for SSH connection messages
2. **Look for certificate-related errors** in the logs
3. **Verify host was reachable** through Teleport proxy
4. **Check task timing** (slow? might be proxy/network issue)

**Expected successful output:**
```
TASK [Gathering Facts] *********************************************************
ok: [host.sean-test.teleport.sh]

PLAY RECAP *********************************************************************
host.sean-test.teleport.sh : ok=1    changed=0    unreachable=0    failed=0
```

---

## Common Issues & Solutions

### Issue 1: "Permission denied (publickey)"

**Symptoms:**
```
fatal: [host.sean-test.teleport.sh]: UNREACHABLE! => {
    "msg": "Failed to connect to the host via ssh: Permission denied (publickey)."
}
```

**Diagnosis:**

```bash
# Check if tbot is running
sudo systemctl status tbot-sean-test.service

# Check if certificate exists
ls -la /var/lib/teleport-bot/sean-test.teleport.sh/out/key-cert.pub

# Check certificate validity
ssh-keygen -L -f /var/lib/teleport-bot/sean-test.teleport.sh/out/key-cert.pub | grep Valid
```

**Possible causes & fixes:**

| Cause | Fix |
|-------|-----|
| tbot not running | `sudo systemctl start tbot-sean-test.service` |
| Certificate expired | Wait 30s for renewal, check `journalctl -u tbot-sean-test.service` |
| Wrong principals | Check cert principals match your ansible_user: `ssh-keygen -L -f ...` |
| Mount not working | Verify in container: `podman exec <id> ls /teleport-bot/` |
| Wrong Teleport login | Update bot role to include correct logins (e.g., ec2-user) |

---

### Issue 2: "Could not resolve hostname"

**Symptoms:**
```
fatal: [myhost]: UNREACHABLE! => {
    "msg": "Failed to connect to the host via ssh: ssh: Could not resolve hostname myhost: ..."
}
```

**Cause:** Using short hostname instead of Teleport FQDN.

**Fix:** Update inventory to use `<host>.<cluster>`:

```yaml
# ❌ Wrong
hosts:
  webserver01:
    ansible_user: ec2-user

# ✅ Correct
hosts:
  webserver01.sean-test.teleport.sh:
    ansible_user: ec2-user
```

---

### Issue 3: tbot service fails to start

**Symptoms:**
```bash
$ sudo systemctl status tbot-sean-test.service
● tbot-sean-test.service - Teleport Machine ID Bot
   Active: failed (Result: exit-code)
```

**Diagnosis:**
```bash
# Check full logs
sudo journalctl -u tbot-sean-test.service -n 100 --no-pager
```

**Common errors and fixes:**

#### A. "Invalid token"
```
ERROR: failed to start: unable to register bot: access denied
```
**Fix:** Token is wrong or expired. Generate new token:
```bash
tctl bots add ansible-aap-bot --roles=your-role --ttl=8760h
# Update token in /var/lib/teleport-bot/sean-test.teleport.sh/tbot.yaml
sudo systemctl restart tbot-sean-test.service
```

#### B. "Connection refused"
```
ERROR: failed to connect to proxy: dial tcp 1.2.3.4:443: connect: connection refused
```
**Fix:**
- Verify proxy address is correct in tbot.yaml
- Check network connectivity: `curl -v https://sean-test.teleport.sh:443`
- Check firewall rules

#### C. "Permission denied" (file access)
```
ERROR: failed to initialize storage: permission denied
```
**Fix:**
```bash
# Fix permissions
sudo chown -R root:root /var/lib/teleport-bot/sean-test.teleport.sh
sudo chmod 700 /var/lib/teleport-bot/sean-test.teleport.sh/data
sudo chmod 755 /var/lib/teleport-bot/sean-test.teleport.sh/out
```

---

### Issue 4: Container can't read mounted files

**Symptoms:**
```
ls: cannot access '/teleport-bot': Permission denied
```

**Cause:** SELinux blocking container access.

**Diagnosis:**
```bash
# Check SELinux status
getenforce

# Check file contexts
ls -Z /var/lib/teleport-bot/sean-test.teleport.sh/out/
```

**Fix:**
```bash
# Apply correct SELinux context
sudo semanage fcontext -a -t container_file_t \
  "/var/lib/teleport-bot/sean-test.teleport.sh/out(/.*)?"
sudo restorecon -Rv /var/lib/teleport-bot/sean-test.teleport.sh/out

# Verify
ls -Z /var/lib/teleport-bot/sean-test.teleport.sh/out/
# Should show: container_file_t
```

If `semanage` is not found:
```bash
# RHEL/CentOS
sudo dnf install policycoreutils-python-utils
```

---

### Issue 5: "ProxyCommand: command not found"

**Symptoms:**
```
ssh_exchange_identification: Connection closed by remote host
```

**Cause:** `tbot` binary not found in container PATH.

**Diagnosis:**
```bash
# Check if tbot is in the EE
podman run -it --rm quay.io/<your-org>/teleport-ssh-ee:latest which tbot
# Should output: /usr/local/bin/tbot
```

**Fix:**
- Rebuild the EE (tbot install step might have failed)
- Check build logs for errors during `curl | bash -s` step

---

### Issue 6: Mount path mismatch

**Symptoms:**
```
Fatal error: Unable to find ssh_config at /teleport-bot/sean-test.teleport.sh.ssh_config
```

**Cause:** Container mount path doesn't match ansible.cfg expectation.

**Fix:** Ensure consistency:

**AAP mount configuration:**
```yaml
# Host path → Container path
/var/lib/teleport-bot/sean-test.teleport.sh/out → /teleport-bot
```

**ansible.cfg:**
```ini
[ssh_connection]
ssh_args = -F /teleport-bot/sean-test.teleport.sh.ssh_config
```

**Generated SSH config filename:**
The tbot daemon creates: `<cluster-name>.ssh_config`
So: `sean-test.teleport.sh.ssh_config`

---

### Issue 7: Multiple jobs running - will they conflict?

**Answer:** No, this is safe by design.

**Why it's safe:**
- Mount is **read-only** to containers (`:ro`)
- Only `tbot` daemon writes (atomic operations)
- Multiple containers reading simultaneously is fine
- Certificates are valid for multiple concurrent connections
- Each SSH connection is independent

**What happens:**
1. tbot (host daemon) refreshes certs → writes to `/var/lib/.../out/`
2. Multiple EE containers read from `/teleport-bot/` simultaneously
3. Each container makes independent SSH connections
4. All use the same valid certificate
5. No locking needed, no conflicts

**However, be aware:**
- Certificate TTL is typically 1 hour
- All jobs share the same Teleport bot identity
- Audit logs will show all actions under the same bot name
- For isolation, use separate bots per team/env

---

### Issue 8: Certificate expired mid-job

**Symptoms:**
Job starts fine but fails partway through with "Permission denied"

**Cause:** Long-running job exceeded certificate TTL.

**Diagnosis:**
```bash
# Check cert validity window
ssh-keygen -L -f /var/lib/teleport-bot/sean-test.teleport.sh/out/key-cert.pub | grep Valid
# Shows: Valid: from 2024-02-04T10:00:00 to 2024-02-04T11:00:00
```

**Fix:**
1. **Increase cert TTL** in Teleport bot config:
   ```yaml
   # In tbot.yaml
   certificate_ttl: 4h  # Default is 1h
   ```
2. **Restart tbot:**
   ```bash
   sudo systemctl restart tbot-sean-test.service
   ```
3. **Or:** Break long playbooks into smaller jobs

**Note:** Ansible opens ONE SSH connection per host and reuses it (ControlPersist). So if the connection is established within cert validity, the job completes fine.

---

### Issue 9: "Warning: Permanently added ... to the list of known hosts"

**Symptoms:**
SSH warnings in output (not fatal but noisy)

**Cause:** `host_key_checking` or missing known_hosts

**Fix in ansible.cfg:**
```ini
[defaults]
host_key_checking = False
```

Or use the known_hosts from tbot:
```ini
[ssh_connection]
ssh_args = -F /teleport-bot/sean-test.teleport.sh.ssh_config -o UserKnownHostsFile=/teleport-bot/known_hosts
```

---

### Issue 10: tbot uses old token after rotation

**Symptoms:**
tbot keeps trying with old token after you rotated it

**Fix:**
```bash
# Stop service
sudo systemctl stop tbot-sean-test.service

# Clear bot state
sudo rm -rf /var/lib/teleport-bot/sean-test.teleport.sh/data/*

# Update token in config
sudo vim /var/lib/teleport-bot/sean-test.teleport.sh/tbot.yaml

# Restart
sudo systemctl start tbot-sean-test.service
```

---

## Advanced Diagnostics

### Enable Verbose SSH Logging

**In ansible.cfg:**
```ini
[ssh_connection]
ssh_args = -F /teleport-bot/sean-test.teleport.sh.ssh_config -vvv
```

**Or set environment variable in AAP job:**
```bash
ANSIBLE_SSH_ARGS="-F /teleport-bot/sean-test.teleport.sh.ssh_config -vvv"
```

This shows detailed SSH handshake, certificate validation, and proxy connection.

### Enable tbot Debug Logging

**In tbot.yaml:**
```yaml
debug: true
```

**Restart tbot:**
```bash
sudo systemctl restart tbot-sean-test.service
```

**View logs:**
```bash
sudo journalctl -u tbot-sean-test.service -f
```

### Test Certificate Manually

```bash
# Extract public key from certificate
ssh-keygen -L -f /var/lib/teleport-bot/sean-test.teleport.sh/out/key-cert.pub

# Manually specify key and cert
ssh -v \
  -i /var/lib/teleport-bot/sean-test.teleport.sh/out/key \
  -o CertificateFile=/var/lib/teleport-bot/sean-test.teleport.sh/out/key-cert.pub \
  -o ProxyCommand="tbot ssh-proxy-command --destination-dir=/var/lib/teleport-bot/sean-test.teleport.sh/out --proxy-server=sean-test.teleport.sh:443 --cluster=sean-test.teleport.sh --user=%r --host=%h --port=%p" \
  ec2-user@host.sean-test.teleport.sh hostname
```

---

## Performance Tuning

### SSH Connection Pooling

Ansible reuses SSH connections via ControlMaster. This is already optimized in the provided ansible.cfg:

```ini
[ssh_connection]
pipelining = True
control_path = /tmp/ansible-ssh-%%h-%%p-%%r
```

**Benefits:**
- Opens 1 SSH connection per host, reuses for all tasks
- Dramatically reduces handshake overhead
- Teleport certificate is validated once per host

### Parallelism

```ini
[defaults]
forks = 20  # Increase for more parallel hosts
```

**Note:** Each fork is a separate process with its own SSH connection. All can read from `/teleport-bot/` simultaneously without conflict.

---

## Security Monitoring

### Audit tbot Certificate Usage

**View tbot activity:**
```bash
sudo journalctl -u tbot-sean-test.service --since "1 hour ago"
```

**Check Teleport audit log:**
```bash
# Via tctl (requires admin access)
tctl audit search --from=1h --format=json | jq '.[] | select(.event=="cert.create")'
```

**Monitor SSH connections:**
```bash
# On Teleport proxy
tsh audit search --from=1h --event=session.start --login=ansible-bot
```

### Detect Anomalies

Watch for:
- ❌ Certificate requests from unexpected IPs
- ❌ Failed authentication attempts
- ❌ Access to nodes outside expected labels
- ❌ tbot downtime (no cert renewals)

Set up alerting in your monitoring system (Prometheus, DataDog, etc.):

```bash
# Example: Alert if tbot has been down > 5 minutes
systemctl is-active tbot-sean-test.service || send_alert
```

---

## Clean Reinstall

If all else fails, start fresh:

```bash
# Stop and disable service
sudo systemctl stop tbot-sean-test.service
sudo systemctl disable tbot-sean-test.service

# Remove all files
sudo rm -rf /var/lib/teleport-bot/sean-test.teleport.sh
sudo rm -f /etc/systemd/system/tbot-sean-test.service

# Reinstall using setup script
sudo ./setup-execution-node.sh sean-test.teleport.sh YOUR_NEW_TOKEN
```

---

## Getting Help

### Teleport Issues
- **Documentation:** https://goteleport.com/docs/machine-id/
- **Community Slack:** https://goteleport.com/slack
- **GitHub Issues:** https://github.com/gravitational/teleport/issues

### AAP Issues
- **Red Hat Support:** https://access.redhat.com/support
- **Documentation:** https://docs.ansible.com/automation-controller/

### This EE
- Open an issue in this repository with:
  - tbot logs (`journalctl -u tbot-sean-test.service -n 200`)
  - AAP job output (sanitized)
  - `ansible --version` from inside EE
  - `tbot version`
