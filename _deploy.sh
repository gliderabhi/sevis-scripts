#!/bin/bash
# =============================================================
# _deploy.sh — shared deploy function
# Builds JAR locally on Mac, uploads to EC2, runs with java -jar
# Not called directly — sourced by individual deploy scripts
# =============================================================

deploy_service() {
    local SERVICE_NAME="$1"
    local LOCAL_PROJECT_DIR="$2"   # absolute path on Mac

    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

    echo "======================================================"
    echo " Deploying: $SERVICE_NAME"
    echo "======================================================"

    # ── Step 1: Build JAR locally ─────────────────────────────
    echo ">>> [$SERVICE_NAME] Building JAR locally..."
    cd "$LOCAL_PROJECT_DIR"

    if [ ! -f "gradlew" ]; then
        echo "ERROR: gradlew not found in $LOCAL_PROJECT_DIR"
        exit 1
    fi

    # Use Java 21 (Kotlin compiler in Spring Boot 3.2.x is incompatible with Java 25+)
    LOCAL_JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null || echo "")
    if [ -n "$LOCAL_JAVA_HOME" ]; then
        export JAVA_HOME="$LOCAL_JAVA_HOME"
        export PATH="$JAVA_HOME/bin:$PATH"
    fi

    ./gradlew bootJar --no-daemon -q
    if [ $? -ne 0 ]; then
        echo "ERROR: bootJar failed for $SERVICE_NAME"
        exit 1
    fi

    JAR_FILE=$(ls build/libs/*.jar 2>/dev/null | grep -v plain | head -1)
    if [ -z "$JAR_FILE" ]; then
        echo "ERROR: No JAR found in $LOCAL_PROJECT_DIR/build/libs/"
        exit 1
    fi
    echo ">>> Built: $JAR_FILE"

    # ── Step 2: Upload JAR to EC2 ─────────────────────────────
    echo ">>> [$SERVICE_NAME] Uploading JAR to EC2..."
    ssh -i "$EC2_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" "mkdir -p $APP_DIR/jars"
    scp -i "$EC2_KEY" -o StrictHostKeyChecking=no \
        "$JAR_FILE" \
        "$EC2_USER@$EC2_HOST:$APP_DIR/jars/$SERVICE_NAME.jar"

    # ── Step 3: Stop old process, start new one ───────────────
    echo ">>> [$SERVICE_NAME] Restarting on EC2..."
    ssh -i "$EC2_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" bash << ENDSSH
set -e
SERVICE_NAME="$SERVICE_NAME"
PID_FILE="$APP_DIR/\$SERVICE_NAME.pid"
JAR_PATH="$APP_DIR/jars/\$SERVICE_NAME.jar"
LOG_FILE="$LOG_DIR/\$SERVICE_NAME.log"
JAVA_BIN="/usr/lib/jvm/java-17-amazon-corretto.x86_64/bin/java"

mkdir -p "$LOG_DIR"

# Stop existing process
if [ -f "\$PID_FILE" ]; then
    OLD_PID=\$(cat "\$PID_FILE")
    if kill -0 "\$OLD_PID" 2>/dev/null; then
        echo "Stopping PID \$OLD_PID..."
        kill "\$OLD_PID"
        sleep 3
        kill -9 "\$OLD_PID" 2>/dev/null || true
    fi
    rm -f "\$PID_FILE"
fi

# Start new process
nohup \$JAVA_BIN -Xmx256m -Xms64m -jar "\$JAR_PATH" --spring.profiles.active=prod > "\$LOG_FILE" 2>&1 &
NEW_PID=\$!
echo \$NEW_PID > "\$PID_FILE"

sleep 5
if kill -0 "\$NEW_PID" 2>/dev/null; then
    echo ""
    echo "======================================================"
    echo " ✓ \$SERVICE_NAME started (PID \$NEW_PID)"
    echo " Logs: \$LOG_FILE"
    echo "======================================================"
else
    echo "ERROR: \$SERVICE_NAME failed to start."
    tail -30 "\$LOG_FILE"
    exit 1
fi
ENDSSH
}
