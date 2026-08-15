#!/bin/bash
# =============================================================
# watchdog.sh — Health-check and restart dead SEVIS services
# Runs every 5 minutes via systemd timer (sevis-watchdog.timer)
# Checks: process running (by JAR basename) + HTTP health endpoint
# Startup order: eureka → core services → gateway → UIs
# =============================================================

export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"

PROJECT_ROOT="/home/sevis/projects"
SEVIS_ROOT="$PROJECT_ROOT/sevis"
COMMON_ROOT="$PROJECT_ROOT/common"
PHOTOS_ROOT="$PROJECT_ROOT/photos"
KIDS_ROOT="$PROJECT_ROOT/kids-study"
STREAM_ROOT="$PROJECT_ROOT/stream"
ROOMLIST_ROOT="$PROJECT_ROOT/roomlist"
ROOMLIST_UI_DIR="$ROOMLIST_ROOT/roomlist-ui/web"
LOG_DIR="$PROJECT_ROOT/local-logs"
PID_DIR="$PROJECT_ROOT/local-pids"
JAVA="/usr/lib/jvm/java-21-openjdk-amd64/bin/java"
JAVA_OPTS="-Xmx256m -Xms64m"

mkdir -p "$LOG_DIR" "$PID_DIR"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$WATCHDOG_LOG"; }

# ── JAR path for each service ────────────────────────────────
jar_for() {
    case "$1" in
        eureka-server)      echo "$COMMON_ROOT/eureka-server/build/libs/eureka-server-0.0.1-SNAPSHOT.jar" ;;
        user-service)       echo "$COMMON_ROOT/user-service/build/libs/user-service-0.0.1-SNAPSHOT.jar" ;;
        gateway)            echo "$COMMON_ROOT/gateway/build/libs/gateway-0.0.1-SNAPSHOT.jar" ;;
        inventory-service)  echo "$SEVIS_ROOT/inventory-service/build/libs/inventory-service-0.0.1-SNAPSHOT.jar" ;;
        billing-service)    echo "$SEVIS_ROOT/billing-service/build/libs/billing-service-0.0.1-SNAPSHOT.jar" ;;
        orders-service)     echo "$SEVIS_ROOT/orders-service/build/libs/orders-service-0.0.1-SNAPSHOT.jar" ;;
        photo-service)      echo "$PHOTOS_ROOT/photo-service/build/libs/photo-service-0.0.1-SNAPSHOT.jar" ;;
        kids-study-service) echo "$KIDS_ROOT/service/build/libs/kids-study-service-0.0.1-SNAPSHOT.jar" ;;
        stream-service)     echo "$STREAM_ROOT/stream-service/build/libs/stream-service-0.0.1-SNAPSHOT.jar" ;;
        listing-service)    echo "$ROOMLIST_ROOT/listing-service/build/libs/listing-service-0.0.1-SNAPSHOT.jar" ;;
    esac
}

# ── Check if a Java service process is running (by JAR name) ─
# Matches on the JAR's basename, not full path, since services are
# sometimes started with a relative path (cwd-dependent) — matching
# the full absolute path would miss those and let duplicates/stale
# processes linger uncaught (this is what caused the gateway crash
# loop: a relative-path instance held port 8080 that pkill -f on the
# absolute path could never find).
# Also syncs the PID file if it was stale.
java_running() {
    local svc="$1"
    local jar
    jar=$(jar_for "$svc")
    [ -z "$jar" ] && return 1
    local pid
    pid=$(pgrep -f "$(basename "$jar")" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid" > "$PID_DIR/$svc.pid"   # keep PID file fresh
        return 0
    fi
    return 1
}

# ── Check if a UI process is running (by script pattern) ─────
ui_running() {
    local pattern="$1"
    local pid_file="$2"
    local pid
    pid=$(pgrep -f "$pattern" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        [ -n "$pid_file" ] && echo "$pid" > "$pid_file"
        return 0
    fi
    return 1
}

# ── HTTP health check (2xx / 3xx / 401 all mean "up") ────────
http_ok() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "$1" 2>/dev/null)
    [[ "$code" =~ ^[23] ]] || [ "$code" = "401" ]
}

# ── Kill any running instance of a JAR before restarting ─────
# Matches by basename (see java_running) and waits for the process to
# actually exit — not just a fixed sleep — before returning, so
# start_java_service never races a still-shutting-down instance for
# the port (Spring Boot's Eureka deregistration on shutdown can take
# several seconds, longer than a flat 1s sleep covers).
kill_java_service() {
    local svc="$1"
    local jar
    jar=$(jar_for "$svc")
    local jar_name
    jar_name=$(basename "$jar")
    local pids
    pids=$(pgrep -f "$jar_name" 2>/dev/null)
    if [ -n "$pids" ]; then
        log "Killing existing $svc PID(s): $pids"
        kill $pids 2>/dev/null || true
        for _ in $(seq 1 15); do
            pids=$(pgrep -f "$jar_name" 2>/dev/null)
            [ -z "$pids" ] && break
            sleep 1
        done
        pids=$(pgrep -f "$jar_name" 2>/dev/null)
        if [ -n "$pids" ]; then
            log "$svc still alive after 15s — force killing: $pids"
            kill -9 $pids 2>/dev/null || true
            sleep 1
        fi
    fi
    rm -f "$PID_DIR/$svc.pid"
}

# ── Start a Java service ──────────────────────────────────────
start_java_service() {
    local svc="$1"
    local jar
    jar=$(jar_for "$svc")
    if [ ! -f "$jar" ]; then
        log "SKIP $svc — JAR not found"
        return 1
    fi
    kill_java_service "$svc"
    nohup "$JAVA" $JAVA_OPTS -jar "$jar" >> "$LOG_DIR/$svc.log" 2>&1 &
    echo $! > "$PID_DIR/$svc.pid"
    log "STARTED $svc (PID $!)"
}

# ── Wait for Eureka to respond ────────────────────────────────
wait_for_eureka() {
    for i in $(seq 1 30); do
        if http_ok "http://localhost:8761/actuator/health"; then
            log "Eureka ready after ${i}s"
            return 0
        fi
        sleep 1
    done
    log "WARNING: Eureka not ready after 30s — continuing anyway"
}

# ── Restart systemd service if not active or HTTP check fails ─
ensure_systemd_service() {
    local unit="$1"
    local health_url="$2"
    local state
    state=$(systemctl --user is-active "$unit" 2>/dev/null)
    if [ "$state" != "active" ] || { [ -n "$health_url" ] && ! http_ok "$health_url"; }; then
        log "DOWN: $unit (state=$state) — restarting"
        systemctl --user restart "$unit" 2>/dev/null
        log "RESTARTED $unit"
    fi
}

# =============================================================
# Main
# =============================================================

log "--- Watchdog check started ---"

eureka_was_dead=false

# ── 1. Eureka ─────────────────────────────────────────────────
if ! java_running "eureka-server" || ! http_ok "http://localhost:8761/actuator/health"; then
    log "DOWN: eureka-server — restarting"
    start_java_service "eureka-server"
    wait_for_eureka
    eureka_was_dead=true
fi

# ── 2. Core Java services ─────────────────────────────────────
for svc in user-service inventory-service billing-service orders-service photo-service kids-study-service listing-service; do
    if ! java_running "$svc"; then
        log "DOWN: $svc — restarting"
        start_java_service "$svc"
        $eureka_was_dead && sleep 2
    fi
done

# ── 3. Gateway ────────────────────────────────────────────────
if ! java_running "gateway" || ! http_ok "http://localhost:8080/actuator/health"; then
    log "DOWN: gateway — restarting"
    if $eureka_was_dead; then
        log "Waiting 15s for services to register before starting gateway..."
        sleep 15
    fi
    start_java_service "gateway"
fi

# ── 4. sevis-web (Angular :4200) ──────────────────────────────
if ! ui_running "ng serve" "$PID_DIR/sevis-web.pid" || ! http_ok "http://localhost:4200"; then
    if ! http_ok "http://localhost:4200"; then
        log "DOWN: sevis-web — restarting"
        pkill -f "ng serve" 2>/dev/null || true
        sleep 1
        nohup npm --prefix "$SEVIS_ROOT/ui/sevis-web" start >> "$LOG_DIR/sevis-web.log" 2>&1 &
        echo $! > "$PID_DIR/sevis-web.pid"
        log "STARTED sevis-web (PID $!)"
    fi
fi

# ── 5. photos-ui (Angular :4201) ──────────────────────────────
if ! http_ok "http://localhost:4201"; then
    log "DOWN: photos-ui — restarting"
    pkill -f "ng serve --port 4201" 2>/dev/null || true
    sleep 1
    nohup npm --prefix "$PHOTOS_ROOT/photos-ui/web" start >> "$LOG_DIR/photos-ui.log" 2>&1 &
    echo $! > "$PID_DIR/photos-ui.pid"
    log "STARTED photos-ui (PID $!)"
fi

# ── 5b. roomlist-ui (Angular :4202) ───────────────────────────
if ! http_ok "http://localhost:4202"; then
    log "DOWN: roomlist-ui — restarting"
    pkill -f "ng serve --port 4202" 2>/dev/null || true
    sleep 1
    nohup npm --prefix "$ROOMLIST_UI_DIR" start >> "$LOG_DIR/roomlist-ui.log" 2>&1 &
    echo $! > "$PID_DIR/roomlist-ui.pid"
    log "STARTED roomlist-ui (PID $!)"
fi

# ── 6. kids-study-ui (Angular :3010) ──────────────────────────
if ! http_ok "http://localhost:3010"; then
    log "DOWN: kids-study-ui — restarting"
    pkill -f "ng serve.*3010" 2>/dev/null || true
    sleep 1
    nohup npm --prefix "$KIDS_ROOT/ui" start >> "$LOG_DIR/kids-study-ui.log" 2>&1 &
    echo $! > "$PID_DIR/kids-study-ui.pid"
    log "STARTED kids-study-ui (PID $!)"
fi

# ── 6b. sevis-root (static :4210) — bare sevis.store placeholder ─────
if ! http_ok "http://localhost:4210"; then
    log "DOWN: sevis-root — restarting"
    pkill -f "serve-spa.js.*4210" 2>/dev/null || true
    sleep 1
    nohup node "$PROJECT_ROOT/sevis-scripts/serve-spa.js" "$PROJECT_ROOT/sevis-root-placeholder/dist" 4210 "" \
        >> "$LOG_DIR/sevis-root.log" 2>&1 &
    echo $! > "$PID_DIR/sevis-root.pid"
    log "STARTED sevis-root (PID $!)"
fi

# ── 7. aria2c RPC (required for stream-service torrent downloads) ─
if ! pgrep -x aria2c > /dev/null; then
    log "DOWN: aria2c — restarting"
    BT_TRACKERS="http://nyaa.tracker.wf:7777/announce,https://tracker.gbitt.info/announce,http://tracker.bt4g.com:2095/announce,udp://tracker.opentrackr.org:1337/announce,udp://open.demonii.com:1337/announce,udp://open.stealth.si:80/announce,udp://tracker.torrent.eu.org:451/announce,udp://explodie.org:6969/announce,udp://exodus.desync.com:6969/announce"
    aria2c --enable-rpc --rpc-listen-all=false --rpc-listen-port=6800 --rpc-secret=stream-secret \
        --dir=/mnt/sdb1/videos/raw --seed-time=0 --max-concurrent-downloads=5 \
        --file-allocation=none --continue=true \
        --enable-dht=true --dht-listen-port=6881 \
        --bt-enable-lpd=true --enable-peer-exchange=true \
        --bt-tracker="$BT_TRACKERS" --bt-max-peers=100 \
        --daemon=true --log="$LOG_DIR/aria2c.log" --log-level=warn
    log "STARTED aria2c (RPC → localhost:6800)"
fi

# ── 8. stream-service ─────────────────────────────────────────
if ! java_running "stream-service" || ! http_ok "http://localhost:8095/api/videos"; then
    log "DOWN: stream-service — restarting"
    STREAM_JAR=$(jar_for "stream-service")
    kill_java_service "stream-service"
    nohup "$JAVA" -Xmx512m -Xms128m -jar "$STREAM_JAR" >> "$LOG_DIR/stream-service.log" 2>&1 &
    echo $! > "$PID_DIR/stream-service.pid"
    log "STARTED stream-service (PID $!)"
fi

# ── 9. Systemd-managed services ───────────────────────────────
ensure_systemd_service "eci-results.service"       "http://localhost:3000"
ensure_systemd_service "yt-dlp-downloader.service" "http://localhost:5050"
ensure_systemd_service "sevis-portal.service"      "http://localhost:5051"
ensure_systemd_service "jackett.service"           "http://localhost:9117"

log "--- Watchdog check complete ---"
