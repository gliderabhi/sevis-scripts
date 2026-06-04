#!/bin/bash
# =============================================================
# pull-db.sh — Dump all SEVIS databases from EC2 and restore locally
# Usage: bash scripts/pull-db.sh
# Requires: mysql client installed locally (brew install mysql-client)
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

DUMP_DIR="$PROJECT_ROOT/db-dumps"
mkdir -p "$DUMP_DIR"

DATABASES=(billing_db inventory_db orders_db user_db)

DB_USER="sevis"
DB_PASS="SevisDb@2024"

LOCAL_ROOT_USER="root"    # local MySQL root user
LOCAL_ROOT_PASS=""        # set if your local root has a password

mysql_local() {
  if [ -n "$LOCAL_ROOT_PASS" ]; then
    mysql -u "$LOCAL_ROOT_USER" -p"$LOCAL_ROOT_PASS" "$@"
  else
    mysql -u "$LOCAL_ROOT_USER" "$@"
  fi
}

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║        SEVIS — Pull DB from EC2              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  EC2 host : $EC2_HOST"
echo "  Databases: ${DATABASES[*]}"
echo "  Dumps dir: $DUMP_DIR"
echo ""

# ── Step 1: Dump each DB on EC2 and copy down ────────────────
echo "[1] Dumping databases on EC2..."
for db in "${DATABASES[@]}"; do
  REMOTE_DUMP="/tmp/${db}.sql"
  LOCAL_DUMP="$DUMP_DIR/${db}.sql"

  echo "    Dumping $db..."
  ssh -i "$EC2_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" \
    "mysqldump -u $DB_USER -p'$DB_PASS' --single-transaction --routines --triggers $db > $REMOTE_DUMP"

  if [ $? -ne 0 ]; then
    echo "    ✗ mysqldump failed for $db — aborting."
    exit 1
  fi

  echo "    Downloading $db dump..."
  scp -i "$EC2_KEY" -o StrictHostKeyChecking=no \
    "$EC2_USER@$EC2_HOST:$REMOTE_DUMP" "$LOCAL_DUMP"

  if [ $? -ne 0 ]; then
    echo "    ✗ scp failed for $db — aborting."
    exit 1
  fi

  SIZE=$(du -sh "$LOCAL_DUMP" | cut -f1)
  echo "    ✓ $db → $LOCAL_DUMP ($SIZE)"

  # Clean up remote dump file
  ssh -i "$EC2_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" "rm -f $REMOTE_DUMP"
done

# ── Step 2: Restore locally ───────────────────────────────────
echo ""
echo "[2] Restoring databases locally..."

# Ensure local sevis user exists
mysql_local -e "
  CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
" 2>/dev/null

for db in "${DATABASES[@]}"; do
  LOCAL_DUMP="$DUMP_DIR/${db}.sql"

  echo "    Restoring $db..."
  mysql_local -e "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  mysql_local -e "GRANT ALL PRIVILEGES ON \`$db\`.* TO '$DB_USER'@'localhost';"
  mysql_local "$db" < "$LOCAL_DUMP"

  if [ $? -ne 0 ]; then
    echo "    ✗ Restore failed for $db"
    exit 1
  fi

  echo "    ✓ $db restored"
done

mysql_local -e "FLUSH PRIVILEGES;"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║           All databases synced!              ║"
echo "╠══════════════════════════════════════════════╣"
for db in "${DATABASES[@]}"; do
  printf "║  %-42s║\n" "  $db"
done
echo "╠══════════════════════════════════════════════╣"
echo "║  Dumps saved → $DUMP_DIR"
echo "╚══════════════════════════════════════════════╝"
echo ""
