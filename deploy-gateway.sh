#!/bin/bash
source "$(dirname "$0")/_deploy.sh"
source "$(dirname "$0")/config.sh"
deploy_service "gateway" "$GATEWAY_REPO" "8080"
