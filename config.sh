#!/bin/bash
# =============================================================
# config.sh — shared configuration for all deploy scripts
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"


EC2_HOST="32.194.147.195"                                    # SEVIS microservices server
EC2_HOST_ECI="ec2-184-72-141-110.compute-1.amazonaws.com"       # ECI result analysis server
EC2_USER="ec2-user"
EC2_KEY="$SCRIPT_DIR/sevis.pem"
APP_DIR="/home/ec2-user/sevis"
LOG_DIR="/home/ec2-user/sevis/logs"

JAVA_HOME="/usr/lib/jvm/java-17-amazon-corretto.x86_64"

# Local project directories (for building JARs on Mac)
COMMON_DIR="$PROJECT_ROOT/sevis-common"
EUREKA_DIR="$PROJECT_ROOT/eureka-server"
GATEWAY_DIR="$PROJECT_ROOT/gateway"
USER_DIR="$PROJECT_ROOT/user-service"
INVENTORY_DIR="$PROJECT_ROOT/inventory-service"
BILLING_DIR="$PROJECT_ROOT/billing-service"
ORDERS_DIR="$PROJECT_ROOT/orders-service"

SSH_CMD="ssh -i $EC2_KEY -o StrictHostKeyChecking=no $EC2_USER@$EC2_HOST"
