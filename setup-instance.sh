#!/bin/bash
# =============================================================
# setup-instance.sh
# Run this ONCE on a fresh EC2 instance to install all
# required software: Java 17, Gradle 8.7, Git
# =============================================================

source "$(dirname "$0")/config.sh"

echo "======================================================"
echo " Setting up EC2 instance at $EC2_HOST"
echo "======================================================"

ssh -i "$EC2_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" bash << 'ENDSSH'

set -e

echo ">>> Updating package manager..."
if command -v yum &>/dev/null; then
    sudo yum update -y
    PKG_MANAGER="yum"
elif command -v apt-get &>/dev/null; then
    sudo apt-get update -y
    PKG_MANAGER="apt"
fi

# ── Java 17 ────────────────────────────────────────────────
echo ">>> Installing Java 17..."
if [ "$PKG_MANAGER" = "yum" ]; then
    sudo yum install -y java-17-amazon-corretto-headless
elif [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt-get install -y openjdk-17-jdk
fi

java -version

# ── Gradle 8.7 ─────────────────────────────────────────────
echo ">>> Installing Gradle 8.7..."
GRADLE_VERSION="8.7"
GRADLE_ZIP="gradle-${GRADLE_VERSION}-bin.zip"

cd /tmp
curl -sL "https://services.gradle.org/distributions/${GRADLE_ZIP}" -o "$GRADLE_ZIP"
sudo unzip -qo "$GRADLE_ZIP" -d /opt/gradle
sudo ln -sf "/opt/gradle/gradle-${GRADLE_VERSION}/bin/gradle" /usr/local/bin/gradle
rm -f "$GRADLE_ZIP"

gradle --version

# ── Git ─────────────────────────────────────────────────────
echo ">>> Installing Git..."
if [ "$PKG_MANAGER" = "yum" ]; then
    sudo yum install -y git
elif [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt-get install -y git
fi

git --version

# ── App & log directories ───────────────────────────────────
echo ">>> Creating directories..."
sudo mkdir -p /opt/sevis
sudo mkdir -p /var/log/sevis
sudo chown -R "$USER":"$USER" /opt/sevis
sudo chown -R "$USER":"$USER" /var/log/sevis

echo ""
echo "======================================================"
echo " Setup complete!"
echo "======================================================"
ENDSSH
