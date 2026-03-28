#!/bin/bash
# =============================================================
# deploy-all.sh
# Pulls latest code for all services and restarts them.
# Run from your local machine:  bash scripts/deploy-all.sh
# =============================================================

set -e
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/config.sh"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║         SEVIS — Full Deployment               ║"
echo "║         Target: $EC2_HOST                     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Step 1: Pull + rebuild sevis-common ──────────────────────
echo "[0/6] Updating sevis-common..."
$SSH_CMD bash << ENDSSH
set -e
export JAVA_HOME="$JAVA_HOME"
export PATH="\$JAVA_HOME/bin:\$PATH"
export GRADLE_OPTS="$GRADLE_OPTS"

cd "$APP_DIR/sevis-common"
git fetch origin && git reset --hard origin/main
./gradlew publishToMavenLocal --no-daemon -q
echo "sevis-common published"
ENDSSH

# ── Step 2: Stop all running services ────────────────────────
echo ""
echo "[*] Stopping all services..."
$SSH_CMD bash "$APP_DIR/stop-all.sh" 2>/dev/null || true
sleep 3

# ── Step 3: Deploy in startup order ──────────────────────────
echo ""
echo "[1/6] Deploying Eureka Server..."
bash "$SCRIPTS_DIR/deploy-eureka-server.sh"
echo ">>> Waiting 30s for Eureka to be ready..."
sleep 30

echo "[2/6] Deploying User Service..."
bash "$SCRIPTS_DIR/deploy-user-service.sh"

echo "[3/6] Deploying Inventory Service..."
bash "$SCRIPTS_DIR/deploy-inventory-service.sh"

echo "[4/6] Deploying Billing Service..."
bash "$SCRIPTS_DIR/deploy-billing-service.sh"

echo "[5/6] Deploying Orders Service..."
bash "$SCRIPTS_DIR/deploy-orders-service.sh"

echo ">>> Waiting 20s for services to register with Eureka..."
sleep 20

echo "[6/6] Deploying Gateway..."
bash "$SCRIPTS_DIR/deploy-gateway.sh"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║           All services deployed!              ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Eureka Dashboard → http://$EC2_HOST:8761    ║"
echo "║  API Gateway      → http://$EC2_HOST:8080    ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
