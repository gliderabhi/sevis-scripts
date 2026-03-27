#!/bin/bash
source "$(dirname "$0")/_deploy.sh"
source "$(dirname "$0")/config.sh"
deploy_service "inventory-service" "$INVENTORY_REPO" "8082"
