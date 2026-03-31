#!/bin/bash
# =============================================================
# run-local.sh — Start all SEVIS services locally
# Usage: bash scripts/run-local.sh
#        bash scripts/run-local.sh stop
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/local-logs"
PID_DIR="$PROJECT_ROOT/local-pids"

JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null)
JAVA="$JAVA_HOME/bin/java"

mkdir -p "$LOG_DIR" "$PID_DIR"

# ── Service definitions: name → project dir ───────────────────
declare -A SERVICE_DIRS=(
  [eureka-server]="$PROJECT_ROOT/eureka-server"
  [gateway]="$PROJECT_ROOT/gateway"
  [user-service]="$PROJECT_ROOT/user-service"
  [inventory-service]="$PROJECT_ROOT/inventory-service"
  [billing-service]="$PROJECT_ROOT/billing-service"
  [orders-service]="$PROJECT_ROOT/orders-service"
)

# Startup order matters — eureka first, gateway last
SERVICES=(eureka-server user-service inventory-service billing-service orders-service gateway)

# ── Stop ──────────────────────────────────────────────────────
stop_all() {
  echo "Stopping all local services..."
  for svc in "${SERVICES[@]}"; do
    PID_FILE="$PID_DIR/$svc.pid"
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" && echo "  Stopped $svc (PID $PID)"
      fi
      rm -f "$PID_FILE"
    fi
  done
  echo "Done."
}

if [ "$1" = "stop" ]; then
  stop_all
  exit 0
fi

# ── Build sevis-common ────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║       SEVIS — Local Development Stack        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

echo "[0] Publishing sevis-common to local Maven..."
cd "$PROJECT_ROOT/sevis-common"
JAVA_HOME=$JAVA_HOME ./gradlew publishToMavenLocal --no-daemon -q
echo "    ✓ sevis-common ready"

# ── Build all JARs ────────────────────────────────────────────
echo ""
echo "[1] Building all service JARs..."
for svc in "${SERVICES[@]}"; do
  DIR="${SERVICE_DIRS[$svc]}"
  echo "    Building $svc..."
  cd "$DIR"
  JAVA_HOME=$JAVA_HOME ./gradlew bootJar --no-daemon -q
  if [ $? -ne 0 ]; then
    echo "    ✗ Build failed for $svc — aborting."
    exit 1
  fi
  echo "    ✓ $svc built"
done

# ── Start services ────────────────────────────────────────────
echo ""
echo "[2] Starting services..."

start_service() {
  local svc="$1"
  local dir="${SERVICE_DIRS[$svc]}"
  local jar=$(ls "$dir/build/libs/"*.jar 2>/dev/null | grep -v plain | head -1)
  local log="$LOG_DIR/$svc.log"
  local pid_file="$PID_DIR/$svc.pid"

  if [ -z "$jar" ]; then
    echo "    ✗ No JAR found for $svc"
    return 1
  fi

  nohup "$JAVA" -Xmx256m -Xms64m -jar "$jar" > "$log" 2>&1 &
  echo $! > "$pid_file"
  echo "    ✓ $svc started (PID $!) → $log"
}

# Start eureka first and wait
start_service "eureka-server"
echo "    Waiting 20s for Eureka to be ready..."
sleep 20

# Start backend services in parallel
for svc in user-service inventory-service billing-service orders-service; do
  start_service "$svc"
done

echo "    Waiting 15s for services to register..."
sleep 15

# Start gateway last
start_service "gateway"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║           All services running!              ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Eureka   → http://localhost:8761            ║"
echo "║  Gateway  → http://localhost:8080            ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Logs     → $LOG_DIR"
echo "║  Stop     → bash scripts/run-local.sh stop  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
