#!/bin/bash
# =============================================================
# Shared config — fill these in before running any script
# =============================================================

EC2_HOST="YOUR_EC2_PUBLIC_IP"          # e.g. 54.123.45.67
EC2_USER="ec2-user"                    # ec2-user (Amazon Linux) or ubuntu (Ubuntu)
EC2_KEY="~/.ssh/your-key.pem"          # path to your .pem key file
APP_DIR="/opt/sevis"                   # base directory on the EC2 instance
LOG_DIR="/var/log/sevis"               # log directory on the EC2 instance

# GitHub repos
EUREKA_REPO="https://github.com/gliderabhi/eureka-server"
GATEWAY_REPO="https://github.com/gliderabhi/gateway"
USER_REPO="https://github.com/gliderabhi/user-service"
INVENTORY_REPO="https://github.com/gliderabhi/inventory-service"
BILLING_REPO="https://github.com/gliderabhi/billing-service"
ORDERS_REPO="https://github.com/gliderabhi/orders-service"
