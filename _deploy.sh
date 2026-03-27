#!/bin/bash
# =============================================================
# _deploy.sh — shared deploy function
# Not called directly. Sourced by individual deploy scripts.
# =============================================================

deploy_service() {
    local SERVICE_NAME="$1"
    local REPO_URL="$2"
    local PORT="$3"

    source "$(dirname "$0")/config.sh"

    echo "======================================================"
    echo " Deploying $SERVICE_NAME → port $PORT"
    echo "======================================================"

    ssh -i "$EC2_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" bash << ENDSSH

set -e

SERVICE_NAME="$SERVICE_NAME"
REPO_URL="$REPO_URL"
PORT="$PORT"
APP_DIR="$APP_DIR/\$SERVICE_NAME"
LOG_FILE="$LOG_DIR/\$SERVICE_NAME.log"
PID_FILE="/tmp/\$SERVICE_NAME.pid"

echo ">>> [\$SERVICE_NAME] Pulling latest code..."
if [ -d "\$APP_DIR/.git" ]; then
    cd "\$APP_DIR"
    git fetch origin
    git reset --hard origin/main
else
    git clone "\$REPO_URL" "\$APP_DIR"
    cd "\$APP_DIR"
fi

echo ">>> [\$SERVICE_NAME] Building JAR..."
cd "\$APP_DIR"
gradle bootJar --no-daemon -q

JAR_FILE=\$(ls "\$APP_DIR"/build/libs/*.jar 2>/dev/null | grep -v plain | head -1)
if [ -z "\$JAR_FILE" ]; then
    echo "ERROR: JAR not found after build!"
    exit 1
fi
echo ">>> Built: \$JAR_FILE"

echo ">>> [\$SERVICE_NAME] Stopping old process (if any)..."
if [ -f "\$PID_FILE" ]; then
    OLD_PID=\$(cat "\$PID_FILE")
    if kill -0 "\$OLD_PID" 2>/dev/null; then
        kill "\$OLD_PID"
        sleep 2
        echo ">>> Stopped PID \$OLD_PID"
    fi
    rm -f "\$PID_FILE"
fi

# Also kill anything holding the port
fuser -k "\$PORT/tcp" 2>/dev/null || true
sleep 1

echo ">>> [\$SERVICE_NAME] Starting service on port \$PORT..."
nohup java -jar "\$JAR_FILE" \
    --server.port="\$PORT" \
    > "\$LOG_FILE" 2>&1 &

NEW_PID=\$!
echo \$NEW_PID > "\$PID_FILE"

sleep 3
if kill -0 "\$NEW_PID" 2>/dev/null; then
    echo ""
    echo "======================================================"
    echo " ✓ \$SERVICE_NAME is running (PID \$NEW_PID, port \$PORT)"
    echo " Logs: \$LOG_FILE"
    echo "======================================================"
else
    echo "ERROR: \$SERVICE_NAME failed to start. Check \$LOG_FILE"
    tail -30 "\$LOG_FILE"
    exit 1
fi

ENDSSH
}
