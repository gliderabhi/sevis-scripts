#!/bin/bash
# =============================================================
# restore-db-local.sh — Restore EC2 DB dumps into local MySQL
# Run with: sudo bash sevis-scripts/restore-db-local.sh
# =============================================================

DUMP_DIR="$(cd "$(dirname "$0")/.." && pwd)/db-dumps"
DB_USER="sevis"
DB_PASS="SevisDb@2024"

DATABASES=(billing_db inventory_db orders_db user_db photo_db)

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     SEVIS — Restore DBs from EC2 dumps       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Create sevis MySQL user if not exists
echo "[1] Setting up local MySQL user '$DB_USER'..."
mysql -u root -e "
  CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
  CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY '';
  ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';
  FLUSH PRIVILEGES;
" 2>/dev/null

echo "    ✓ MySQL users configured"

# Restore each database
echo ""
echo "[2] Restoring databases..."
for db in "${DATABASES[@]}"; do
  DUMP_FILE="$DUMP_DIR/${db}.sql"

  if [ ! -f "$DUMP_FILE" ]; then
    echo "    ⚠ No dump found for $db — skipping (will be auto-created by service)"
    # Create empty DB so the service can connect
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
    mysql -u root -e "GRANT ALL PRIVILEGES ON \`$db\`.* TO '$DB_USER'@'localhost';" 2>/dev/null
    continue
  fi

  echo "    Restoring $db ($(du -sh "$DUMP_FILE" | cut -f1))..."
  mysql -u root -e "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
  mysql -u root -e "GRANT ALL PRIVILEGES ON \`$db\`.* TO '$DB_USER'@'localhost';" 2>/dev/null
  mysql -u root "$db" < "$DUMP_FILE" 2>/dev/null

  if [ $? -eq 0 ]; then
    echo "    ✓ $db restored"
  else
    echo "    ✗ $db restore failed — check dump file"
  fi
done

mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null

echo ""
echo "[3] Verifying databases..."
mysql -u "$DB_USER" -p"$DB_PASS" -e "SHOW DATABASES;" 2>/dev/null

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║           Database restore complete!         ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  User  : sevis / SevisDb@2024                ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "NOTE: Service application.yml files still use root/empty."
echo "      MySQL root now allows password-less local connections."
