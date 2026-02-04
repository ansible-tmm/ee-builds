# Teleport SSH Execution Environment

Ansible Automation Platform (AAP) Execution Environment for secure SSH via Teleport Machine ID with short-lived certificates.

## What This Provides

- ✅ Certificate-based SSH through Teleport (no long-lived keys)
- ✅ Zero secrets in container images
- ✅ Works with AAP Automation Mesh
- ✅ OpenSSH client + Teleport tbot included
- ✅ SELinux compatible (RHEL)

## Quick Start

### 1. Build the EE

```bash
cd teleport-ssh-ee

ansible-builder build -v 3 \
  --build-arg AH_TOKEN=<your-automation-hub-token> \
  --context=. \
  --tag=teleport-ssh-ee:latest

podman push quay.io/yourorg/teleport-ssh-ee:latest
```

### 2. Setup Execution Node

On each AAP execution node:

```bash
# Run automated setup script
sudo ./setup-execution-node.sh sean-test.teleport.sh "YOUR_BOT_TOKEN"

# Verify tbot is running
sudo systemctl status tbot-sean-test.service

# Check certificates are being generated
ls -la /var/lib/teleport-bot/sean-test.teleport.sh/out/
```

### 3. Configure AAP

**Add the EE:**
- Go to Administration → Execution Environments → Add
- Image: `quay.io/yourorg/teleport-ssh-ee:latest`

**Configure Volume Mount** (Instance Group):

For Kubernetes/OpenShift AAP, add to Pod Spec Override:
```yaml
spec:
  containers:
    - name: worker
      volumeMounts:
        - name: teleport-certs
          mountPath: /teleport-bot
          readOnly: true
  volumes:
    - name: teleport-certs
      hostPath:
        path: /var/lib/teleport-bot/sean-test.teleport.sh/out
        type: Directory
```

For traditional AAP, set in configuration:
```yaml
awx_task_env:
  RUNNER_VOLUME_MOUNT: "/var/lib/teleport-bot/sean-test.teleport.sh/out:/teleport-bot:ro"
```

### 4. Create Project

**ansible.cfg:**
```ini
[defaults]
host_key_checking = False

[ssh_connection]
ssh_args = -F /teleport-bot/sean-test.teleport.sh.ssh_config
pipelining = True
```

**inventory/hosts.yml:**
```yaml
all:
  hosts:
    myhost.sean-test.teleport.sh:  # Use full Teleport FQDN
      ansible_user: ec2-user        # Match Teleport login
```

### 5. Run Job

Create a job template with your EE and launch it. SSH connections will go through Teleport automatically.

## Architecture

```
Execution Node:
  tbot (systemd) → Writes certs to /var/lib/teleport-bot/<cluster>/out/
                         ↓ (bind mount read-only)
  EE Container:
    /teleport-bot/ ← Reads certs
    Ansible → SSH with ProxyCommand → tbot → Teleport Proxy → Target
```

### Key Design Decisions

- **tbot runs on host** (systemd daemon) - more secure, persistent across container restarts
- **tbot binary included in EE** - required for SSH ProxyCommand
- **Read-only mount** - containers cannot tamper with certificates
- **Standardized path** (`/teleport-bot`) - works across all execution nodes

## Directory Structure (Host)

```bash
/var/lib/teleport-bot/
└── sean-test.teleport.sh/          # One per Teleport cluster
    ├── data/                        # Bot state (chmod 700, writable by tbot)
    │   └── token                    # Bot join token (chmod 600)
    ├── out/                         # Certificates (chmod 755, read by containers)
    │   ├── sean-test.teleport.sh.ssh_config
    │   ├── key
    │   ├── key-cert.pub
    │   └── known_hosts
    └── tbot.yaml                    # tbot configuration (chmod 600)
```

## Verification

**On execution node:**
```bash
# Check tbot
sudo systemctl status tbot-sean-test.service

# Check certificates
ls -la /var/lib/teleport-bot/sean-test.teleport.sh/out/
ssh-keygen -L -f /var/lib/teleport-bot/sean-test.teleport.sh/out/key-cert.pub

# Test SSH
ssh -F /var/lib/teleport-bot/sean-test.teleport.sh/out/sean-test.teleport.sh.ssh_config \
  ec2-user@myhost.sean-test.teleport.sh hostname
```

**In container (local test):**
```bash
podman run -it --rm \
  -v /var/lib/teleport-bot/sean-test.teleport.sh/out:/teleport-bot:ro \
  quay.io/yourorg/teleport-ssh-ee:latest \
  /bin/bash

# Inside container
ls -la /teleport-bot/
ssh -F /teleport-bot/sean-test.teleport.sh.ssh_config ec2-user@myhost.sean-test.teleport.sh hostname
```

## Security

### ✅ Best Practices

- **Short-lived certificates**: Default 1 hour TTL, auto-renewed by tbot
- **No secrets in images**: Bot tokens only on execution node hosts
- **Read-only mounts**: Containers cannot modify certificates
- **Separate bots per environment**: Use different bots for prod/staging/dev
- **Minimal Teleport RBAC**: Grant only required node labels and logins
- **SELinux enforcement** (RHEL):
  ```bash
  sudo semanage fcontext -a -t container_file_t "/var/lib/teleport-bot/*/out(/.*)?"
  sudo restorecon -Rv /var/lib/teleport-bot/*/out
  ```

### ❌ Don't Do This

- Don't commit bot tokens to git (see `.gitignore`)
- Don't embed tokens in container images
- Don't use writable mounts for certificate directories
- Don't share bot tokens between environments
- Don't use short hostnames in inventory (must be full Teleport FQDN)

### Teleport Bot Role Example

```yaml
kind: role
version: v7
metadata:
  name: ansible-automation-bot
spec:
  allow:
    logins: ['ec2-user', 'ubuntu']
    node_labels:
      'env': ['production', 'staging']
      'managed-by': ['ansible']
  options:
    max_session_ttl: 1h
```

Create bot:
```bash
tctl bots add ansible-aap-bot --roles=ansible-automation-bot --ttl=8760h
```

## Multi-Cluster Support

To support multiple Teleport clusters, simply:

1. **Run separate tbot daemons** on each execution node:
```bash
/var/lib/teleport-bot/
├── prod.teleport.example.com/
│   ├── data/
│   └── out/
└── staging.teleport.example.com/
    ├── data/
    └── out/
```

2. **Create separate projects** in AAP with cluster-specific `ansible.cfg`:

**Production project:**
```ini
ssh_args = -F /teleport-bot/prod.teleport.example.com.ssh_config
```

**Staging project:**
```ini
ssh_args = -F /teleport-bot/staging.teleport.example.com.ssh_config
```

**Note:** The EE has default env vars `TELEPORT_PROXY` and `TELEPORT_CLUSTER` set to `sean-test.teleport.sh` (for demo purposes). These are not used by the SSH connection - the actual cluster is determined by your `ansible.cfg` path. You don't need to rebuild the EE for different clusters.

## Files Reference

```
teleport-ssh-ee/
├── execution-environment.yml    # ansible-builder config
├── bindep.txt                   # System packages (openssh-clients, etc.)
├── requirements.txt             # Python packages (paramiko, etc.)
├── requirements.yml             # Ansible collections
├── README.md                    # This file
├── TROUBLESHOOTING.md          # Detailed diagnostics
├── setup-execution-node.sh     # Automated host setup
├── ansible.cfg.example         # Ansible configuration template
├── inventory.yml.example       # Sample inventory
├── tbot.yaml.example          # Teleport bot config template
├── tbot.service.example       # systemd service template
└── test-connectivity.yml.example  # Test playbook
```

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for detailed diagnostics.

**Quick fixes:**

| Problem | Quick Fix |
|---------|-----------|
| "Permission denied (publickey)" | Check: `systemctl status tbot-*` and `ls /var/lib/teleport-bot/*/out/` |
| "Could not resolve hostname" | Use full FQDN in inventory: `host.cluster.teleport.sh` |
| tbot won't start | Check logs: `journalctl -u tbot-* -n 50` and verify token |
| Container can't read certs | SELinux: `restorecon -Rv /var/lib/teleport-bot/*/out` |

## Support

- **Teleport**: https://goteleport.com/docs/machine-id/
- **AAP**: Red Hat support
- **This repo**: GitHub issues
