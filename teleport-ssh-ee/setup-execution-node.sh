#!/bin/bash
#
# Host Setup Script for Teleport SSH EE
#
# This script prepares an AAP execution node to use Teleport Machine ID
# for certificate-based SSH access.
#
# Usage:
#   sudo ./setup-execution-node.sh [cluster-name] [bot-token]
#
# Example:
#   sudo ./setup-execution-node.sh sean-test.teleport.sh "YOUR_BOT_TOKEN_HERE"
#

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-sean-test.teleport.sh}"
BOT_TOKEN="${2:-}"
TELEPORT_VERSION="${TELEPORT_VERSION:-17.1.5}"
BASE_DIR="/var/lib/teleport-bot"
CLUSTER_DIR="${BASE_DIR}/${CLUSTER_NAME}"
DATA_DIR="${CLUSTER_DIR}/data"
OUT_DIR="${CLUSTER_DIR}/out"
TBOT_CONFIG="${CLUSTER_DIR}/tbot.yaml"
SERVICE_NAME="tbot-$(echo ${CLUSTER_NAME} | sed 's/\./-/g')"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

echo -e "${GREEN}=== Teleport SSH EE - Execution Node Setup ===${NC}"
echo -e "Cluster: ${CLUSTER_NAME}"
echo -e "Base directory: ${BASE_DIR}"
echo ""

# Step 1: Install Teleport
echo -e "${YELLOW}[1/7] Installing Teleport ${TELEPORT_VERSION}...${NC}"
if ! command -v tbot &> /dev/null; then
    curl -fsSL https://cdn.teleport.dev/install-v17.sh | bash -s ${TELEPORT_VERSION}
    echo -e "${GREEN}✓ Teleport installed${NC}"
else
    echo -e "${GREEN}✓ Teleport already installed ($(tbot version 2>&1 | head -n1))${NC}"
fi

# Step 2: Create directory structure
echo -e "${YELLOW}[2/7] Creating directory structure...${NC}"
mkdir -p "${DATA_DIR}" "${OUT_DIR}"
chmod 700 "${BASE_DIR}"
chmod 700 "${DATA_DIR}"
chmod 755 "${OUT_DIR}"
echo -e "${GREEN}✓ Directories created${NC}"

# Step 3: Create tbot configuration
echo -e "${YELLOW}[3/7] Creating tbot configuration...${NC}"

if [[ -z "${BOT_TOKEN}" ]]; then
    echo -e "${YELLOW}⚠ No bot token provided. You'll need to add it manually to ${TBOT_CONFIG}${NC}"
    TOKEN_LINE="  token: YOUR_TELEPORT_BOT_TOKEN_HERE"
else
    TOKEN_LINE="  token: ${BOT_TOKEN}"
fi

cat > "${TBOT_CONFIG}" <<EOF
version: v2
proxy_server: ${CLUSTER_NAME}:443

onboarding:
  join_method: token
${TOKEN_LINE}

storage:
  type: directory
  path: ${DATA_DIR}

destinations:
  - type: directory
    path: ${OUT_DIR}
    configs:
      - ssh_client
EOF

chmod 600 "${TBOT_CONFIG}"
echo -e "${GREEN}✓ Configuration written to ${TBOT_CONFIG}${NC}"

# Step 4: Create systemd service
echo -e "${YELLOW}[4/7] Creating systemd service...${NC}"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Teleport Machine ID Bot for ${CLUSTER_NAME}
Documentation=https://goteleport.com/docs/machine-id/introduction/
After=network.target

[Service]
Type=simple
User=root
Group=root
Restart=always
RestartSec=5
ExecStart=/usr/local/bin/tbot start -c ${TBOT_CONFIG}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=${CLUSTER_DIR}
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓ Service file created: ${SERVICE_FILE}${NC}"

# Step 5: Configure SELinux (if enabled)
echo -e "${YELLOW}[5/7] Configuring SELinux (if enabled)...${NC}"
if command -v getenforce &> /dev/null && [[ "$(getenforce)" != "Disabled" ]]; then
    if command -v semanage &> /dev/null; then
        semanage fcontext -a -t container_file_t "${OUT_DIR}(/.*)?" 2>/dev/null || true
        restorecon -Rv "${OUT_DIR}"
        echo -e "${GREEN}✓ SELinux context applied${NC}"
    else
        echo -e "${YELLOW}⚠ semanage not found. Install policycoreutils-python-utils for SELinux support${NC}"
    fi
else
    echo -e "${GREEN}✓ SELinux not enabled, skipping${NC}"
fi

# Step 6: Enable and start service
echo -e "${YELLOW}[6/7] Enabling and starting tbot service...${NC}"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"

if [[ -z "${BOT_TOKEN}" ]]; then
    echo -e "${YELLOW}⚠ Skipping service start - please add your bot token to ${TBOT_CONFIG} first${NC}"
    echo -e "  Then run: systemctl start ${SERVICE_NAME}.service"
else
    systemctl start "${SERVICE_NAME}.service"
    sleep 2

    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo -e "${GREEN}✓ Service started successfully${NC}"
    else
        echo -e "${RED}✗ Service failed to start. Check logs: journalctl -u ${SERVICE_NAME}.service -n 50${NC}"
        exit 1
    fi
fi

# Step 7: Verify setup
echo -e "${YELLOW}[7/7] Verifying setup...${NC}"
echo -e "Service status:"
systemctl status "${SERVICE_NAME}.service" --no-pager || true

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Verify certificates are being generated:"
echo -e "     ${GREEN}ls -la ${OUT_DIR}/${NC}"
echo -e ""
echo -e "  2. Check tbot logs:"
echo -e "     ${GREEN}journalctl -u ${SERVICE_NAME}.service -f${NC}"
echo -e ""
echo -e "  3. Test SSH connectivity:"
echo -e "     ${GREEN}ssh -F ${OUT_DIR}/${CLUSTER_NAME}.ssh_config ec2-user@<host>.${CLUSTER_NAME} hostname${NC}"
echo -e ""
echo -e "  4. Configure AAP to mount ${OUT_DIR} to /teleport-bot in EE containers"
echo -e ""
echo -e "Directory structure:"
tree -L 3 "${CLUSTER_DIR}" 2>/dev/null || ls -laR "${CLUSTER_DIR}"
