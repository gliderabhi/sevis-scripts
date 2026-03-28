#!/bin/bash
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/_deploy.sh"
deploy_service "billing-service" "$BILLING_DIR"
