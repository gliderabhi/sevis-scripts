#!/bin/bash
# =============================================================
# deploy-eci-analysis.sh
# Deploys the eci-result-analysis Node.js app to EC2.
# Run from the scripts/ directory: bash scripts/deploy-eci-analysis.sh
# =============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

SSH_CMD="ssh -i $EC2_KEY -o StrictHostKeyChecking=no $EC2_USER@$EC2_HOST_ECI"

SERVICE_NAME="eci-result-analysis"
LOCAL_PROJECT_DIR="$PROJECT_ROOT/$SERVICE_NAME"
REMOTE_DEPLOY_DIR="/home/$EC2_USER/$SERVICE_NAME"

echo "======================================================"
echo " Deploying: $SERVICE_NAME"
echo " Host:      $EC2_HOST_ECI"
echo "======================================================"

# ── Step 1: Package locally ───────────────────────────────────
echo ">>> Packaging application (excluding node_modules)..."
cd "$LOCAL_PROJECT_DIR"
tar -czf /tmp/eci-result-analysis.tar.gz --exclude=node_modules --exclude=.git .

# ── Step 2: Upload ────────────────────────────────────────────
echo ">>> Uploading to EC2..."
$SSH_CMD "mkdir -p $REMOTE_DEPLOY_DIR"
scp -i "$EC2_KEY" -o StrictHostKeyChecking=no \
    /tmp/eci-result-analysis.tar.gz \
    "$EC2_USER@$EC2_HOST_ECI:$REMOTE_DEPLOY_DIR/"

# ── Step 3: Remote setup and start ───────────────────────────
echo ">>> Setting up and starting on EC2..."
$SSH_CMD bash << ENDSSH
set -e

# Install Node.js 20 if not present or too old
if ! command -v node &>/dev/null || [ "\$(node -v 2>/dev/null | cut -d'v' -f2 | cut -d'.' -f1)" -lt 20 ] 2>/dev/null; then
    echo "Installing Node.js 20..."
    curl -sL https://rpm.nodesource.com/setup_20.x | sudo bash - 2>&1 | tail -3
    sudo dnf install -y nodejs 2>&1 | tail -3
fi

# Ensure node/npm are on PATH (nodesource installs to /usr/bin)
export PATH=/usr/local/bin:/usr/bin:\$PATH
echo "Node: \$(node -v)  npm: \$(npm -v)"

# Install PM2 if not present
if ! command -v pm2 &>/dev/null; then
    echo "Installing PM2..."
    sudo npm install -g pm2
fi

# Install system dependencies (Chromium + better-sqlite3 native build)
echo "Installing system dependencies..."
sudo dnf install -y \
    alsa-lib at-spi2-atk cups-libs libdrm libXcomposite \
    libXcursor libXdamage libXext libXfixes libXi libXrandr libXrender \
    libXtst pango mesa-libgbm libxkbcommon libwayland-client libwayland-server nss \
    python3 make gcc gcc-c++ sqlite-devel 2>&1 | tail -3 || true

cd $REMOTE_DEPLOY_DIR

# Extract new code
tar -xzf eci-result-analysis.tar.gz
rm eci-result-analysis.tar.gz

# Install npm dependencies
echo "Running npm install..."
rm -rf node_modules
npm install --production

# Install Playwright's Chromium (used as executablePath by puppeteer-core)
echo "Installing Playwright Chromium..."
npx playwright install chromium 2>&1 | tail -5

# Stop old process and start fresh
pm2 delete eci-result-analysis 2>/dev/null || true
pm2 start server.js --name eci-result-analysis
pm2 save

sleep 3
pm2 show eci-result-analysis | grep -E "status|pid|uptime" || true
echo ""
echo "======================================================"
echo " ✓ eci-result-analysis is running"
echo " URL: http://$EC2_HOST_ECI:3000"
echo "======================================================"
ENDSSH

# ── Cleanup local archive ─────────────────────────────────────
rm /tmp/eci-result-analysis.tar.gz

echo ""
echo "✓ Deployment complete."
