#!/bin/bash
# =============================================================
# deploy-all.sh
# Deploys all services in the correct startup order:
# eureka-server → services → gateway
# =============================================================

set -e
SCRIPTS_DIR="$(dirname "$0")"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║         SEVIS — Full Stack Deployment         ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

echo "[1/6] Deploying Eureka Server..."
bash "$SCRIPTS_DIR/deploy-eureka-server.sh"
echo ">>> Waiting 15s for Eureka to be ready..."
sleep 15

echo "[2/6] Deploying User Service..."
bash "$SCRIPTS_DIR/deploy-user-service.sh"

echo "[3/6] Deploying Inventory Service..."
bash "$SCRIPTS_DIR/deploy-inventory-service.sh"

echo "[4/6] Deploying Billing Service..."
bash "$SCRIPTS_DIR/deploy-billing-service.sh"

echo "[5/6] Deploying Orders Service..."
bash "$SCRIPTS_DIR/deploy-orders-service.sh"

echo ">>> Waiting 10s for services to register with Eureka..."
sleep 10

echo "[6/6] Deploying Gateway..."
bash "$SCRIPTS_DIR/deploy-gateway.sh"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║           All services deployed!              ║"
echo "╠══════════════════════════════════════════════╣"

source "$SCRIPTS_DIR/config.sh"
echo "║  Eureka Dashboard  → http://$EC2_HOST:8761  "
echo "║  Gateway           → http://$EC2_HOST:8080  "
echo "║  User Service      → http://$EC2_HOST:8081  "
echo "║  Inventory Service → http://$EC2_HOST:8082  "
echo "║  Billing Service   → http://$EC2_HOST:8083  "
echo "║  Orders Service    → http://$EC2_HOST:8084  "
echo "╚══════════════════════════════════════════════╝"
echo ""
