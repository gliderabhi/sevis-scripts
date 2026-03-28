#!/bin/bash
# =============================================================
# stop-all.sh — server-side script
# Stops all running Sevis services gracefully.
# Run on the EC2 instance: bash ~/sevis/stop-all.sh
# =============================================================

BASE=~/sevis

stop_service() {
    local NAME=$1
    local PID_FILE=$BASE/$NAME.pid

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "[$NAME] Stopping PID $PID..."
            kill "$PID"
            sleep 2
            # Force kill if still running
            if kill -0 "$PID" 2>/dev/null; then
                kill -9 "$PID" 2>/dev/null || true
            fi
            echo "[$NAME] Stopped."
        else
            echo "[$NAME] Not running."
        fi
        rm -f "$PID_FILE"
    else
        echo "[$NAME] No PID file found."
    fi
}

echo "=== Stopping all Sevis services ==="
stop_service "gateway"
stop_service "user-service"
stop_service "billing-service"
stop_service "inventory-service"
stop_service "orders-service"
stop_service "eureka-server"

# Kill any leftover Gradle/Java processes for sevis
pkill -f "sevis.*bootRun" 2>/dev/null || true
pkill -f "GradleDaemon" 2>/dev/null || true

echo ""
echo "All services stopped."
