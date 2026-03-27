#!/bin/bash
source "$(dirname "$0")/_deploy.sh"
source "$(dirname "$0")/config.sh"
deploy_service "user-service" "$USER_REPO" "8081"
