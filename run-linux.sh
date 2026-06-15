#!/bin/bash
# =============================================================
# run-linux.sh — Start all SEVIS services on Linux
#
# Usage:
#   bash sevis-scripts/run-linux.sh              # build + start all
#   bash sevis-scripts/run-linux.sh --skip-build # start without rebuilding JARs
#   bash sevis-scripts/run-linux.sh --tunnel     # also start Cloudflare tunnels
#   bash sevis-scripts/run-linux.sh stop         # stop everything
#   bash sevis-scripts/run-linux.sh status       # show what's running
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SEVIS_ROOT="$PROJECT_ROOT/sevis"
COMMON_ROOT="$PROJECT_ROOT/common"
PHOTOS_ROOT="$PROJECT_ROOT/photos"
LOG_DIR="$PROJECT_ROOT/local-logs"
PID_DIR="$PROJECT_ROOT/local-pids"

# Detect Java 21
if [ -d "/usr/lib/jvm/java-21-openjdk-amd64" ]; then
  JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
elif [ -d "/usr/lib/jvm/java-21-openjdk" ]; then
  JAVA_HOME="/usr/lib/jvm/java-21-openjdk"
elif [ -d "/usr/lib/jvm/temurin-21" ]; then
  JAVA_HOME="/usr/lib/jvm/temurin-21"
else
  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
fi
JAVA="$JAVA_HOME/bin/java"

SEVIS_SERVICES="eureka-server user-service inventory-service billing-service orders-service gateway"
PHOTO_SERVICE_DIR="$PHOTOS_ROOT/photo-service"
PHOTOS_UI_DIR="$PHOTOS_ROOT/photos-ui"
WEB_DIR="$SEVIS_ROOT/ui/sevis-web"
INDEX_HTML="$WEB_DIR/src/index.html"
PHOTOS_INDEX_HTML="$PHOTOS_UI_DIR/src/index.html"

ALL_PROCESSES="eureka-server user-service inventory-service billing-service orders-service photo-service gateway sevis-web photos-ui tunnel-gateway tunnel-web tunnel-photos"

mkdir -p "$LOG_DIR" "$PID_DIR"

# ── Helpers ───────────────────────────────────────────────────

service_dir() {
  case "$1" in
    eureka-server)     echo "$COMMON_ROOT/eureka-server" ;;
    gateway)           echo "$COMMON_ROOT/gateway" ;;
    user-service)      echo "$COMMON_ROOT/user-service" ;;
    inventory-service) echo "$SEVIS_ROOT/inventory-service" ;;
    billing-service)   echo "$SEVIS_ROOT/billing-service" ;;
    orders-service)    echo "$SEVIS_ROOT/orders-service" ;;
    photo-service)     echo "$PHOTO_SERVICE_DIR" ;;
  esac
}

inject_api_url() {
  sed -i '/window\.__SEVIS_API_URL__/d' "$INDEX_HTML"
  sed -i "s|<base href=\"/\">|<base href=\"/\">\n  <script>window.__SEVIS_API_URL__ = '$1';</script>|" "$INDEX_HTML"
  echo "    ✓ Injected SEVIS API URL: $1"
}

remove_api_url() {
  [ -f "$INDEX_HTML" ] && sed -i '/window\.__SEVIS_API_URL__/d' "$INDEX_HTML"
}

inject_photos_api_url() {
  sed -i '/window\.__PHOTOS_API_URL__/d' "$PHOTOS_INDEX_HTML"
  sed -i "s|<base href=\"/\">|<base href=\"/\">\n  <script>window.__PHOTOS_API_URL__ = '$1';</script>|" "$PHOTOS_INDEX_HTML"
  echo "    ✓ Injected Photos API URL: $1"
}

remove_photos_api_url() {
  [ -f "$PHOTOS_INDEX_HTML" ] && sed -i '/window\.__PHOTOS_API_URL__/d' "$PHOTOS_INDEX_HTML"
}

is_running() {
  local pid_file="$PID_DIR/$1.pid"
  [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

# ── Stop ──────────────────────────────────────────────────────

stop_all() {
  echo "Stopping all SEVIS services..."
  for svc in $ALL_PROCESSES; do
    local pid_file="$PID_DIR/$svc.pid"
    if [ -f "$pid_file" ]; then
      local pid
      pid=$(cat "$pid_file")
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" && echo "  Stopped $svc (PID $pid)"
      fi
      rm -f "$pid_file"
    fi
  done
  remove_api_url
  remove_photos_api_url
  echo "Done."
}

# ── Status ────────────────────────────────────────────────────

show_status() {
  echo ""
  echo "┌────────────────────────────────────────────┐"
  echo "│              SEVIS Service Status           │"
  echo "├──────────────────────────┬─────────────────┤"
  printf "│ %-24s │ %-15s │\n" "Service" "Status"
  echo "├──────────────────────────┼─────────────────┤"
  for svc in $ALL_PROCESSES; do
    local pid_file="$PID_DIR/$svc.pid"
    if [ -f "$pid_file" ]; then
      local pid
      pid=$(cat "$pid_file")
      if kill -0 "$pid" 2>/dev/null; then
        printf "│ %-24s │ \e[32mrunning (%-5s)\e[0m │\n" "$svc" "$pid"
      else
        printf "│ %-24s │ \e[31mdead (stale PID)\e[0m │\n" "$svc"
      fi
    else
      printf "│ %-24s │ \e[90mstopped\e[0m         │\n" "$svc"
    fi
  done
  echo "└──────────────────────────┴─────────────────┘"
  echo ""
}

# ── Argument parsing ──────────────────────────────────────────

if [ "$1" = "stop" ];   then stop_all;    exit 0; fi
if [ "$1" = "status" ]; then show_status; exit 0; fi

SKIP_BUILD=0
WITH_TUNNEL=0
for arg in "$@"; do
  [ "$arg" = "--skip-build" ] && SKIP_BUILD=1
  [ "$arg" = "--tunnel" ]     && WITH_TUNNEL=1
done

# ── Banner ────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║       SEVIS — Local Development Stack        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Build sevis-common ────────────────────────────────────────

if [ "$SKIP_BUILD" = "0" ]; then
  echo "[0] Publishing sevis-common to local Maven..."
  cd "$SEVIS_ROOT/sevis-common" || { echo "✗ sevis-common not found"; exit 1; }
  JAVA_HOME=$JAVA_HOME ./gradlew publishToMavenLocal --no-daemon -q
  echo "    ✓ sevis-common published"

  # ── Build all JARs ──────────────────────────────────────────

  echo ""
  echo "[1] Building all service JARs..."
  for svc in $SEVIS_SERVICES photo-service; do
    local_dir="$(service_dir "$svc")"
    if [ -z "$local_dir" ] || [ ! -d "$local_dir" ]; then
      echo "    ⚠ Skipping $svc — directory not found"
      continue
    fi
    echo "    Building $svc..."
    cd "$local_dir"
    JAVA_HOME=$JAVA_HOME ./gradlew bootJar --no-daemon -q
    if [ $? -ne 0 ]; then
      echo "    ✗ Build failed for $svc — aborting."
      exit 1
    fi
    echo "    ✓ $svc built"
  done
else
  echo "[0/1] Skipping build (--skip-build)"
fi

# ── Start Java services ───────────────────────────────────────

start_java_service() {
  local svc="$1"
  local dir
  dir="$(service_dir "$svc")"
  local jar
  jar=$(ls "$dir/build/libs/"*.jar 2>/dev/null | grep -v plain | head -1)
  local log="$LOG_DIR/$svc.log"
  local pid_file="$PID_DIR/$svc.pid"

  if is_running "$svc"; then
    echo "    ⚠ $svc already running (PID $(cat "$pid_file")) — skipping"
    return 0
  fi

  if [ -z "$jar" ]; then
    echo "    ✗ No JAR found for $svc"
    return 1
  fi

  nohup "$JAVA" -Xmx256m -Xms64m -jar "$jar" > "$log" 2>&1 &
  echo $! > "$pid_file"
  echo "    ✓ $svc started (PID $!) → $log"
}

echo ""
echo "[2] Starting Java services..."

start_java_service "eureka-server"
echo "    Waiting for Eureka to be ready..."
for i in $(seq 1 40); do
  if curl -s http://localhost:8761/actuator/health 2>/dev/null | grep -q '"UP"'; then
    echo "    ✓ Eureka is up (${i}s)"
    break
  fi
  sleep 1
done

for svc in user-service inventory-service billing-service orders-service photo-service; do
  start_java_service "$svc"
done

echo "    Waiting 15s for services to register with Eureka..."
sleep 15

start_java_service "gateway"

# ── Cloudflare tunnels (optional) ─────────────────────────────

GATEWAY_TUNNEL_URL=""
WEB_TUNNEL_URL=""
PHOTOS_TUNNEL_URL="https://photos.sevis.store"

if [ "$WITH_TUNNEL" = "1" ]; then
  echo ""
  echo "[3] Starting Cloudflare tunnels..."

  nohup cloudflared tunnel --url http://localhost:8080 --logfile "$LOG_DIR/tunnel-gateway.log" > /dev/null 2>&1 &
  echo $! > "$PID_DIR/tunnel-gateway.pid"

  nohup cloudflared tunnel --url http://localhost:4200 --logfile "$LOG_DIR/tunnel-web.log" > /dev/null 2>&1 &
  echo $! > "$PID_DIR/tunnel-web.pid"

  nohup cloudflared tunnel --hostname photos.sevis.store --url http://localhost:4201 --logfile "$LOG_DIR/tunnel-photos.log" > /dev/null 2>&1 &
  echo $! > "$PID_DIR/tunnel-photos.pid"
  echo "    ✓ Photos tunnel: $PHOTOS_TUNNEL_URL"

  echo "    Waiting 8s for tunnel URLs to appear..."
  sleep 8

  GATEWAY_TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG_DIR/tunnel-gateway.log" 2>/dev/null | head -1)
  WEB_TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG_DIR/tunnel-web.log" 2>/dev/null | head -1)

  if [ -n "$GATEWAY_TUNNEL_URL" ]; then
    inject_api_url "$GATEWAY_TUNNEL_URL"
    inject_photos_api_url "$GATEWAY_TUNNEL_URL"
    echo "    ✓ Gateway tunnel: $GATEWAY_TUNNEL_URL"
  else
    echo "    ✗ Could not detect gateway tunnel URL — check $LOG_DIR/tunnel-gateway.log"
  fi

  [ -n "$WEB_TUNNEL_URL" ] && echo "    ✓ Web tunnel:     $WEB_TUNNEL_URL" \
    || echo "    ✗ Could not detect web tunnel URL — check $LOG_DIR/tunnel-web.log"
else
  remove_api_url
  remove_photos_api_url
fi

# ── Start Angular UIs ─────────────────────────────────────────

start_ui() {
  local name="$1"
  local dir="$2"
  local step="$3"
  local port="$4"

  echo ""
  echo "[$step] Starting $name (port $port)..."

  if is_running "$name"; then
    echo "    ⚠ $name already running (PID $(cat "$PID_DIR/$name.pid")) — skipping"
    return 0
  fi

  if [ ! -d "$dir" ]; then
    echo "    ✗ $name directory not found: $dir"
    return 1
  fi

  # Clean reinstall if rollup Linux native module is missing (common after cross-OS checkout)
  if [ ! -d "$dir/node_modules" ] || ! ls "$dir/node_modules/@rollup/rollup-linux-x64-gnu" &>/dev/null; then
    if [ -d "$dir/node_modules" ]; then
      echo "    Rollup Linux native module missing — cleaning node_modules..."
      rm -rf "$dir/node_modules" "$dir/package-lock.json"
    fi
    echo "    Installing npm dependencies for $name..."
    cd "$dir" && npm install --silent
  fi

  cd "$dir"
  nohup npm start > "$LOG_DIR/$name.log" 2>&1 &
  echo $! > "$PID_DIR/$name.pid"
  echo "    ✓ $name started (PID $!) → $LOG_DIR/$name.log"
}

start_ui "sevis-web"  "$WEB_DIR"      4 4200
start_ui "photos-ui"  "$PHOTOS_UI_DIR" 5 4201

# ── Summary ───────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║           All services running!              ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Eureka   → http://localhost:8761            ║"
echo "║  Gateway  → http://localhost:8080            ║"
echo "║  SEVIS UI → http://localhost:4200            ║"
echo "║  Photos   → http://localhost:4201            ║"
if [ -n "$GATEWAY_TUNNEL_URL" ]; then
echo "╠══════════════════════════════════════════════╣"
printf "║  Gateway  → %-32s║\n" "$GATEWAY_TUNNEL_URL"
printf "║  Web UI   → %-32s║\n" "$WEB_TUNNEL_URL"
printf "║  Photos   → %-32s║\n" "$PHOTOS_TUNNEL_URL"
fi
echo "╠══════════════════════════════════════════════╣"
echo "║  Logs   → $LOG_DIR"
echo "║  Stop   → bash sevis-scripts/run-linux.sh stop"
echo "║  Status → bash sevis-scripts/run-linux.sh status"
echo "╚══════════════════════════════════════════════╝"
echo ""
