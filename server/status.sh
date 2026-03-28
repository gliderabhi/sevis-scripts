#!/bin/bash
# =============================================================
# status.sh — server-side script
# Shows running status of all Sevis services.
# Run on the EC2 instance: bash ~/sevis/status.sh
# =============================================================

BASE=~/sevis

check_service() {
    local NAME=$1
    local PID_FILE=$BASE/$NAME.pid

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "  ✓ $NAME  (PID $PID)"
        else
            echo "  ✗ $NAME  (PID $PID — not running, stale PID file)"
        fi
    else
        echo "  ✗ $NAME  (not started)"
    fi
}

echo ""
echo "╔══════════════════════════════════════╗"
echo "║       Sevis Services Status          ║"
echo "╚══════════════════════════════════════╝"
check_service "eureka-server"
check_service "gateway"
check_service "user-service"
check_service "billing-service"
check_service "inventory-service"
check_service "orders-service"

echo ""
echo "Memory usage:"
free -h | grep -E "Mem|Swap"

echo ""
echo "Eureka registered services:"
curl -s http://localhost:8761/eureka/apps 2>/dev/null \
    | grep -o '<app><name>[^<]*' \
    | sed 's/<app><name>/  - /' \
    || echo "  (Eureka not reachable)"
echo ""
