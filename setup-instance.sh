#!/bin/bash
# =============================================================
# setup-instance.sh
# One-time setup for a fresh Amazon Linux 2023 EC2 instance.
# Run from your local machine:  bash scripts/setup-instance.sh
# =============================================================

set -e
source "$(dirname "$0")/config.sh"

echo "======================================================"
echo " Setting up EC2 instance at $EC2_HOST"
echo "======================================================"

$SSH_CMD bash << 'ENDSSH'
set -e

echo ">>> Adding 2GB swap (prevents OOM on t2.micro)..."
if [ ! -f /swapfile ]; then
    sudo dd if=/dev/zero of=/swapfile bs=128M count=16
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab
    echo "Swap added."
else
    echo "Swap already exists."
fi

echo ">>> Installing Java 17 + JDK..."
sudo dnf install -y java-17-amazon-corretto java-17-amazon-corretto-devel git 2>&1 | tail -3
java -version 2>&1
javac -version

echo ">>> Setting JAVA_HOME..."
JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto.x86_64
grep -q "JAVA_HOME" ~/.bashrc || echo "export JAVA_HOME=$JAVA_HOME" >> ~/.bashrc
grep -q "GRADLE_OPTS" ~/.bashrc || echo 'export GRADLE_OPTS="-Xmx256m -Xms64m"' >> ~/.bashrc
grep -q "$JAVA_HOME/bin" ~/.bashrc || echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc

echo ">>> Installing MySQL 8..."
if ! command -v mysql &>/dev/null; then
    sudo dnf install -y https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm 2>&1 | tail -2
    sudo dnf install -y mysql-community-server --nogpgcheck 2>&1 | tail -3
fi
sudo systemctl enable mysqld
sudo systemctl start mysqld

echo ">>> Creating databases and user..."
TEMP_PASS=$(sudo grep 'temporary password' /var/log/mysqld.log 2>/dev/null | awk '{print $NF}' | tail -1)
if [ -n "$TEMP_PASS" ]; then
    mysql -u root -p"$TEMP_PASS" --connect-expired-password -e "
        ALTER USER 'root'@'localhost' IDENTIFIED BY 'SevisRoot@2024';
        CREATE DATABASE IF NOT EXISTS user_db;
        CREATE DATABASE IF NOT EXISTS orders_db;
        CREATE DATABASE IF NOT EXISTS billing_db;
        CREATE DATABASE IF NOT EXISTS inventory_db;
        CREATE USER IF NOT EXISTS 'sevis'@'localhost' IDENTIFIED BY 'SevisDb@2024';
        GRANT ALL PRIVILEGES ON user_db.*      TO 'sevis'@'localhost';
        GRANT ALL PRIVILEGES ON orders_db.*    TO 'sevis'@'localhost';
        GRANT ALL PRIVILEGES ON billing_db.*   TO 'sevis'@'localhost';
        GRANT ALL PRIVILEGES ON inventory_db.* TO 'sevis'@'localhost';
        FLUSH PRIVILEGES;
    " 2>/dev/null && echo "MySQL configured." || echo "MySQL already configured, skipping."
else
    echo "MySQL already configured."
fi

echo ">>> Cloning repositories..."
export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto.x86_64
export GRADLE_OPTS="-Xmx256m -Xms64m"
mkdir -p ~/sevis && cd ~/sevis

for repo in sevis-common eureka-server gateway user-service billing-service inventory-service orders-service; do
    if [ ! -d "$repo/.git" ]; then
        git clone "https://github.com/gliderabhi/$repo.git"
    else
        echo "$repo already cloned, skipping."
    fi
done

echo ">>> Copying gradle-wrapper.jar to all services..."
WRAPPER_JAR=~/sevis/sevis-common/gradle/wrapper/gradle-wrapper.jar
for svc in eureka-server gateway user-service billing-service inventory-service orders-service; do
    mkdir -p ~/sevis/$svc/gradle/wrapper
    cp "$WRAPPER_JAR" ~/sevis/$svc/gradle/wrapper/
    chmod +x ~/sevis/$svc/gradlew
done

echo ">>> Building sevis-common..."
cd ~/sevis/sevis-common
./gradlew publishToMavenLocal --no-daemon -q
echo "sevis-common published."

echo ">>> Uploading server-side scripts..."
# (scripts are uploaded separately by setup-instance.sh caller)

echo ">>> Pre-downloading all service dependencies..."
for svc in eureka-server gateway user-service billing-service inventory-service orders-service; do
    echo "  Resolving: $svc"
    cd ~/sevis/$svc && ./gradlew dependencies --no-daemon -q 2>&1 | tail -1
done

mkdir -p ~/sevis/logs

echo ""
echo "======================================================"
echo " Setup complete! Run deploy-all.sh to start services."
echo "======================================================"
ENDSSH

# ── Upload server-side management scripts ────────────────────
echo ""
echo ">>> Uploading server management scripts..."
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
scp -i "$EC2_KEY" -o StrictHostKeyChecking=no \
    "$SCRIPTS_DIR/server/start-all.sh" \
    "$SCRIPTS_DIR/server/stop-all.sh" \
    "$SCRIPTS_DIR/server/status.sh" \
    "$EC2_USER@$EC2_HOST:/home/ec2-user/sevis/"
$SSH_CMD "chmod +x ~/sevis/start-all.sh ~/sevis/stop-all.sh ~/sevis/status.sh"
echo "Server scripts uploaded."

echo ""
echo "======================================================"
echo " Instance setup complete!"
echo " Next: bash scripts/deploy-all.sh"
echo "======================================================"
