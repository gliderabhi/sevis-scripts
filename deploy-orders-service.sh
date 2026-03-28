#!/bin/bash
source "$(dirname "$0")/_deploy.sh"
source "$(dirname "$0")/config.sh"
deploy_service "orders-service" "$ORDERS_REPO"
