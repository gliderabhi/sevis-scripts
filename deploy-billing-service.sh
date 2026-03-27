#!/bin/bash
source "$(dirname "$0")/_deploy.sh"
source "$(dirname "$0")/config.sh"
deploy_service "billing-service" "$BILLING_REPO" "8083"
