#!/bin/bash
# =============================================================
# run-local.sh — Start all SEVIS services locally
# Usage: bash sevis-scripts/run-local.sh [--tunnel]
#        bash sevis-scripts/run-local.sh stop
#
# --tunnel  Also starts Cloudflare tunnels and injects the
#           gateway URL into the web UI so remote laptops work.
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SEVIS_ROOT="$PROJECT_ROOT/sevis"
COMMON_ROOT="$PROJECT_ROOT/common"
PHOTOS_ROOT="$PROJECT_ROOT/photos"
LOG_DIR="$PROJECT_ROOT/local-logs"
PID_DIR="$PROJECT_ROOT/local-pids"

# Detect JAVA_HOME: macOS → Linux → Windows (Eclipse Adoptium)
if command -v /usr/libexec/java_home &>/dev/null; then
  JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null)
elif [ -d "/usr/lib/jvm/java-21-openjdk-amd64" ]; then
  JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
else
  JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot"
fi
JAVA="$JAVA_HOME/bin/java"

mkdir -p "$LOG_DIR" "$PID_DIR"

# Startup order matters — eureka first, gateway last
SERVICES="eureka-server user-service inventory-service billing-service orders-service gateway"

PHOTO_SERVICE_DIR="$PHOTOS_ROOT/photo-service"
PHOTOS_UI_DIR="$PHOTOS_ROOT/photos-ui"
WEB_DIR="$SEVIS_ROOT/ui/sevis-web"
INDEX_HTML="$WEB_DIR/src/index.html"
PHOTOS_INDEX_HTML="$PHOTOS_UI_DIR/src/index.html"

# ── Map service name → project dir ───────────────────────────
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

# ── Inject / remove gateway URL override in index.html ───────
inject_api_url() {
  local url="$1"
  sed -i '' '/window\.__SEVIS_API_URL__/d' "$INDEX_HTML"
  sed -i '' "s|<base href=\"/\">|<base href=\"/\">\n  <script>window.__SEVIS_API_URL__ = '$url';</script>|" "$INDEX_HTML"
  echo "    ✓ Injected API URL: $url"
}

remove_api_url() {
  sed -i '' '/window\.__SEVIS_API_URL__/d' "$INDEX_HTML" 2>/dev/null
}

inject_photos_api_url() {
  local url="$1"
  sed -i '' '/window\.__PHOTOS_API_URL__/d' "$PHOTOS_INDEX_HTML"
  sed -i '' "s|<base href=\"/\">|<base href=\"/\">\n  <script>window.__PHOTOS_API_URL__ = '$url';</script>|" "$PHOTOS_INDEX_HTML"
  echo "    ✓ Injected Photos API URL: $url"
}

remove_photos_api_url() {
  sed -i '' '/window\.__PHOTOS_API_URL__/d' "$PHOTOS_INDEX_HTML" 2>/dev/null
}

# ── Stop ──────────────────────────────────────────────────────
stop_all() {
  echo "Stopping all local services..."
  for svc in $SERVICES photo-service sevis-web photos-ui tunnel-gateway tunnel-web tunnel-photos; do
    PID_FILE="$PID_DIR/$svc.pid"
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" && echo "  Stopped $svc (PID $PID)"
      fi
      rm -f "$PID_FILE"
    fi
  done
  remove_api_url
  remove_photos_api_url
  echo "Done."
}

if [ "$1" = "stop" ]; then
  stop_all
  exit 0
fi

WITH_TUNNEL=0
if [ "$1" = "--tunnel" ]; then
  WITH_TUNNEL=1
fi

# ── Build sevis-common ────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║       SEVIS — Local Development Stack        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

echo "[0] Publishing sevis-common to local Maven..."
cd "$SEVIS_ROOT/sevis-common"
JAVA_HOME=$JAVA_HOME ./gradlew publishToMavenLocal --no-daemon -q
echo "    ✓ sevis-common ready"

# ── Build all JARs ────────────────────────────────────────────
echo ""
echo "[1] Building all service JARs..."
for svc in $SERVICES photo-service; do
  DIR="$(service_dir $svc)"
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
  local dir="$(service_dir $svc)"
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

start_service "eureka-server"
echo "    Waiting for Eureka to be ready..."
for i in $(seq 1 30); do
  if curl -s http://localhost:8761/actuator/health | grep -q "UP"; then
    echo "    ✓ Eureka is up (${i}s)"
    break
  fi
  sleep 1
done

for svc in user-service inventory-service billing-service orders-service photo-service; do
  start_service "$svc"
done

echo "    Waiting 15s for services to register with Eureka..."
sleep 15

start_service "gateway"

# ── Cloudflare tunnels (optional) ────────────────────────────
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
  echo "    ✓ Photos tunnel:  $PHOTOS_TUNNEL_URL"

  echo "    Waiting for tunnel URLs..."
  sleep 6

  GATEWAY_TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG_DIR/tunnel-gateway.log" 2>/dev/null | head -1)
  WEB_TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG_DIR/tunnel-web.log" 2>/dev/null | head -1)

  if [ -n "$GATEWAY_TUNNEL_URL" ]; then
    inject_api_url "$GATEWAY_TUNNEL_URL"
    inject_photos_api_url "$GATEWAY_TUNNEL_URL"
    echo "    ✓ Gateway tunnel: $GATEWAY_TUNNEL_URL"
  else
    echo "    ✗ Could not detect gateway tunnel URL — check $LOG_DIR/tunnel-gateway.log"
  fi

  if [ -n "$WEB_TUNNEL_URL" ]; then
    echo "    ✓ Web tunnel:     $WEB_TUNNEL_URL"
  else
    echo "    ✗ Could not detect web tunnel URL — check $LOG_DIR/tunnel-web.log"
  fi
else
  remove_api_url
  remove_photos_api_url
fi

# ── Start sevis-web ───────────────────────────────────────────
echo ""
echo "[4] Starting sevis-web..."
if [ ! -d "$WEB_DIR/node_modules" ]; then
  echo "    Installing npm dependencies..."
  cd "$WEB_DIR" && npm install --silent
fi
cd "$WEB_DIR"
nohup npm start > "$LOG_DIR/sevis-web.log" 2>&1 &
echo $! > "$PID_DIR/sevis-web.pid"
echo "    ✓ sevis-web started (PID $!) → $LOG_DIR/sevis-web.log"

echo ""
echo "[5] Starting photos-ui..."
if [ ! -d "$PHOTOS_UI_DIR/node_modules" ]; then
  echo "    Installing npm dependencies..."
  cd "$PHOTOS_UI_DIR" && npm install --silent
fi
cd "$PHOTOS_UI_DIR"
nohup npm start > "$LOG_DIR/photos-ui.log" 2>&1 &
echo $! > "$PID_DIR/photos-ui.pid"
echo "    ✓ photos-ui started (PID $!) → $LOG_DIR/photos-ui.log"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║           All services running!              ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Eureka   → http://localhost:8761            ║"
echo "║  Gateway  → http://localhost:8080            ║"
echo "║  Web UI   → http://localhost:4200            ║"
echo "║  Photos   → http://localhost:4201            ║"
if [ -n "$GATEWAY_TUNNEL_URL" ]; then
echo "╠══════════════════════════════════════════════╣"
printf "║  Gateway  → %-32s║\n" "$GATEWAY_TUNNEL_URL"
printf "║  Web UI   → %-32s║\n" "$WEB_TUNNEL_URL"
printf "║  Photos   → %-32s║\n" "$PHOTOS_TUNNEL_URL"
echo "║  (share URLs with other laptops)             ║"
fi
echo "╠══════════════════════════════════════════════╣"
echo "║  Logs → $LOG_DIR"
echo "║  Stop → bash sevis-scripts/run-local.sh stop ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
