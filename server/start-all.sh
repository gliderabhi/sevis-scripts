#!/bin/bash
# =============================================================
# start-all.sh — server-side script
# Starts all Sevis services in the correct order using pre-built JARs.
# Run on the EC2 instance: bash ~/sevis/start-all.sh
# =============================================================

JAVA=/usr/lib/jvm/java-17-amazon-corretto.x86_64/bin/java
BASE=~/sevis
JARS=$BASE/jars
LOG=$BASE/logs
mkdir -p $LOG

start_service() {
    local NAME=$1
    local PID_FILE=$BASE/$NAME.pid
    local JAR=$JARS/$NAME.jar

    if [ ! -f "$JAR" ]; then
        echo "[$NAME] JAR not found at $JAR — skipping."
        return
    fi

    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        echo "[$NAME] Already running (PID $(cat $PID_FILE)), skipping."
        return
    fi

    echo "[$NAME] Starting..."
    nohup $JAVA -Xmx256m -Xms64m -jar "$JAR" --spring.profiles.active=prod > "$LOG/$NAME.log" 2>&1 &
    echo $! > $PID_FILE
    echo "[$NAME] Started (PID $!)"
}

echo "=== Starting Eureka Server ==="
start_service "eureka-server"
echo ">>> Waiting 35s for Eureka to be ready..."
sleep 35

echo "=== Starting Microservices ==="
start_service "user-service"
sleep 5
start_service "billing-service"
sleep 5
start_service "inventory-service"
sleep 5
start_service "orders-service"
echo ">>> Waiting 20s for services to register..."
sleep 20

echo "=== Starting Gateway ==="
start_service "gateway"
sleep 5

echo ""
echo "All services started. Logs at $LOG/"
echo "Eureka: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null):8761"
echo "Gateway: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null):8080"
