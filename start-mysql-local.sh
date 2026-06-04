#!/bin/bash
# Start local MySQL server (run this if MySQL is not already running)
MYSQL_BIN="/c/Program Files/MySQL/MySQL Server 8.4/bin"
MYSQL_CNF="C:/ProgramData/MySQL/MySQL Server 8.4/my.ini"

if "$MYSQL_BIN/mysql.exe" -u root --connect-timeout=2 -e "SELECT 1;" &>/dev/null; then
  echo "MySQL is already running."
  exit 0
fi

echo "Starting MySQL..."
nohup "$MYSQL_BIN/mysqld.exe" "--defaults-file=$MYSQL_CNF" --console > /tmp/mysqld.log 2>&1 &
echo $! > /tmp/mysqld.pid
echo "Waiting for MySQL to be ready..."
for i in $(seq 1 15); do
  if "$MYSQL_BIN/mysql.exe" -u root --connect-timeout=2 -e "SELECT 1;" &>/dev/null; then
    echo "✓ MySQL is up (PID $(cat /tmp/mysqld.pid))"
    exit 0
  fi
  sleep 1
done
echo "✗ MySQL failed to start — check /tmp/mysqld.log"
exit 1
