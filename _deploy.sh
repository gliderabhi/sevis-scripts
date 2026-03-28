#!/bin/bash
# =============================================================
# _deploy.sh — shared deploy function
# Pulls latest code and restarts a service on the EC2 instance
# Not called directly — sourced by individual deploy scripts
# =============================================================

deploy_service() {
    local SERVICE_NAME="$1"
    local REPO_URL="$2"

    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

    echo "======================================================"
    echo " Deploying: $SERVICE_NAME"
    echo "======================================================"

    $SSH_CMD bash << ENDSSH
set -e
export JAVA_HOME="$JAVA_HOME"
export PATH="\$JAVA_HOME/bin:\$PATH"
export GRADLE_OPTS="$GRADLE_OPTS"

SERVICE_NAME="$SERVICE_NAME"
REPO_URL="$REPO_URL"
APP_DIR="$APP_DIR/\$SERVICE_NAME"
LOG_DIR="$LOG_DIR"
PID_FILE="$APP_DIR/\$SERVICE_NAME.pid"

mkdir -p "\$LOG_DIR"

echo ">>> [\$SERVICE_NAME] Pulling latest code..."
if [ -d "\$APP_DIR/.git" ]; then
    cd "\$APP_DIR"
    git fetch origin
    git reset --hard origin/main
else
    git clone "\$REPO_URL" "\$APP_DIR"
    cd "\$APP_DIR"
    # copy gradle-wrapper.jar if missing
    if [ ! -f "gradle/wrapper/gradle-wrapper.jar" ]; then
        mkdir -p gradle/wrapper
        cp "$APP_DIR/../sevis-common/gradle/wrapper/gradle-wrapper.jar" gradle/wrapper/
    fi
fi

echo ">>> [\$SERVICE_NAME] Stopping old process (if any)..."
if [ -f "\$PID_FILE" ]; then
    OLD_PID=\$(cat "\$PID_FILE")
    if kill -0 "\$OLD_PID" 2>/dev/null; then
        kill "\$OLD_PID"
        sleep 3
        echo ">>> Stopped PID \$OLD_PID"
    fi
    rm -f "\$PID_FILE"
fi

echo ">>> [\$SERVICE_NAME] Starting service..."
cd "\$APP_DIR"
chmod +x gradlew
nohup ./gradlew bootRun --no-daemon > "\$LOG_DIR/\$SERVICE_NAME.log" 2>&1 &
NEW_PID=\$!
echo \$NEW_PID > "\$PID_FILE"

sleep 5
if kill -0 "\$NEW_PID" 2>/dev/null; then
    echo ""
    echo "======================================================"
    echo " ✓ \$SERVICE_NAME started (PID \$NEW_PID)"
    echo " Logs: \$LOG_DIR/\$SERVICE_NAME.log"
    echo "======================================================"
else
    echo "ERROR: \$SERVICE_NAME failed to start."
    tail -30 "\$LOG_DIR/\$SERVICE_NAME.log"
    exit 1
fi
ENDSSH
}
