#!/bin/bash
# =============================================================
# watchdog.sh — Restart any dead SEVIS services
# Runs every 5 minutes via cron. Checks each PID file;
# if the process is gone, restarts that service.
# Startup order: eureka → core services → gateway
# =============================================================

PROJECT_ROOT="/home/sevis/projects"
SEVIS_ROOT="$PROJECT_ROOT/sevis"
COMMON_ROOT="$PROJECT_ROOT/common"
LOG_DIR="$PROJECT_ROOT/local-logs"
PID_DIR="$PROJECT_ROOT/local-pids"
JAVA="/usr/lib/jvm/java-21-openjdk-amd64/bin/java"
JAVA_OPTS="-Xmx256m -Xms64m"

mkdir -p "$LOG_DIR" "$PID_DIR"

WATCHDOG_LOG="$LOG_DIR/watchdog.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"
}

# ── JAR path for each service ────────────────────────────────
jar_for() {
    local svc="$1"
    case "$svc" in
        eureka-server)     echo "$COMMON_ROOT/eureka-server/build/libs/eureka-server-0.0.1-SNAPSHOT.jar" ;;
        user-service)      echo "$COMMON_ROOT/user-service/build/libs/user-service-0.0.1-SNAPSHOT.jar" ;;
        gateway)           echo "$COMMON_ROOT/gateway/build/libs/gateway-0.0.1-SNAPSHOT.jar" ;;
        inventory-service) echo "$SEVIS_ROOT/inventory-service/build/libs/inventory-service-0.0.1-SNAPSHOT.jar" ;;
        billing-service)   echo "$SEVIS_ROOT/billing-service/build/libs/billing-service-0.0.1-SNAPSHOT.jar" ;;
        orders-service)    echo "$SEVIS_ROOT/orders-service/build/libs/orders-service-0.0.1-SNAPSHOT.jar" ;;
    esac
}

# ── Check if a service is alive ──────────────────────────────
is_alive() {
    local svc="$1"
    local pid_file="$PID_DIR/$svc.pid"
    [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

# ── Start a single service ───────────────────────────────────
start_service() {
    local svc="$1"
    local jar="$(jar_for $svc)"

    if [ ! -f "$jar" ]; then
        log "SKIP $svc — JAR not found: $jar"
        return 1
    fi

    local log_file="$LOG_DIR/$svc.log"
    nohup "$JAVA" $JAVA_OPTS -jar "$jar" >> "$log_file" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_DIR/$svc.pid"
    log "STARTED $svc (PID $pid)"
}

# ── Wait for Eureka to be ready ──────────────────────────────
wait_for_eureka() {
    for i in $(seq 1 30); do
        if curl -s http://localhost:8761/actuator/health 2>/dev/null | grep -q "UP"; then
            log "Eureka ready after ${i}s"
            return 0
        fi
        sleep 1
    done
    log "WARNING: Eureka not ready after 30s — continuing anyway"
}

# ── Main watchdog logic ──────────────────────────────────────

eureka_was_dead=false

# 1. Eureka first — everything depends on it
if ! is_alive "eureka-server"; then
    log "DOWN: eureka-server — restarting"
    start_service "eureka-server"
    wait_for_eureka
    eureka_was_dead=true
fi

# 2. Core services (order doesn't matter, can start in parallel)
for svc in user-service inventory-service billing-service orders-service; do
    if ! is_alive "$svc"; then
        log "DOWN: $svc — restarting"
        start_service "$svc"
        # If eureka just came back, give services a moment to register
        if $eureka_was_dead; then
            sleep 2
        fi
    fi
done

# 3. Gateway last — needs other services registered with Eureka
if ! is_alive "gateway"; then
    log "DOWN: gateway — restarting"
    # If other services were just restarted, give them time to register
    if $eureka_was_dead; then
        log "Waiting 15s for services to register before starting gateway..."
        sleep 15
    fi
    start_service "gateway"
fi

# 4. sevis-web (ng serve) — restart if dead
if ! is_alive "sevis-web"; then
    log "DOWN: sevis-web — restarting"
    WEB_DIR="$SEVIS_ROOT/ui/sevis-web"
    nohup npm --prefix "$WEB_DIR" start >> "$LOG_DIR/sevis-web.log" 2>&1 &
    echo $! > "$PID_DIR/sevis-web.pid"
    log "STARTED sevis-web (PID $!)"
fi

log "Watchdog check complete"
