#!/bin/bash
# =============================================================
# deploy-all.sh
# Builds all JARs locally and deploys to EC2 in correct order.
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

# ── Step 0: Build and publish sevis-common locally ───────────
echo "[0/6] Building sevis-common..."
cd "$COMMON_DIR"
./gradlew publishToMavenLocal --no-daemon -q
echo "sevis-common published to local Maven."

# ── Step 1: Stop all running services on EC2 ─────────────────
echo ""
echo "[*] Stopping all services on EC2..."
$SSH_CMD "bash $APP_DIR/stop-all.sh" 2>/dev/null || true
sleep 2

# ── Step 2: Deploy in startup order ──────────────────────────
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
