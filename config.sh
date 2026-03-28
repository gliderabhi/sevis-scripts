#!/bin/bash
# =============================================================
# config.sh — shared configuration for all deploy scripts
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EC2_HOST="32.194.147.195"
EC2_USER="ec2-user"
EC2_KEY="$SCRIPT_DIR/sevis.pem"
APP_DIR="/home/ec2-user/sevis"
LOG_DIR="/home/ec2-user/sevis/logs"

JAVA_HOME="/usr/lib/jvm/java-17-amazon-corretto.x86_64"
GRADLE_OPTS="-Xmx256m -Xms64m"

# GitHub repos
COMMON_REPO="https://github.com/gliderabhi/sevis-common"
EUREKA_REPO="https://github.com/gliderabhi/eureka-server"
GATEWAY_REPO="https://github.com/gliderabhi/gateway"
USER_REPO="https://github.com/gliderabhi/user-service"
INVENTORY_REPO="https://github.com/gliderabhi/inventory-service"
BILLING_REPO="https://github.com/gliderabhi/billing-service"
ORDERS_REPO="https://github.com/gliderabhi/orders-service"

SSH_CMD="ssh -i $EC2_KEY -o StrictHostKeyChecking=no $EC2_USER@$EC2_HOST"
