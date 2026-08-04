#!/usr/bin/env bash
set -e

export STELLAR_HOME="/opt/stellar"
export HZHOME="$STELLAR_HOME/horizon"
export PGHOME="$STELLAR_HOME/postgresql"
export PGDATA="/var/lib/postgresql/16/main"
export PGBIN="/usr/lib/postgresql/16/bin"
export PGUSER="stellar"
export PGPORT=5432
export PGPASS="stellar"

echo "=== Stellar Horizon - Initializing ==="
echo "Core Version: $(stellar-core version 2>/dev/null | head -1)"
echo "Horizon Version: $(stellar-horizon version 2>/dev/null | head -1)"
echo "Network: Test SDF Network ; September 2015"

# ============================================================
# 1. Prepare directories and configs
# ============================================================
mkdir -p "$HZHOME/etc" "$HZHOME/captive-core" "$PGDATA" /var/run/postgresql
chown -R stellar:stellar "$HZHOME" 2>/dev/null || true
chown -R postgres:postgres "$PGDATA" /var/run/postgresql 2>/dev/null || true

# Fix SSL permissions (PostgreSQL bug in container)
chown root:root /etc/ssl/private 2>/dev/null || true
chmod 0711 /etc/ssl/private 2>/dev/null || true
find /etc/ssl/private -type f -exec chmod 0640 {} \; 2>/dev/null || true

# Copy configs from staging if they do not exist on the volume
if [ ! -f "$HZHOME/etc/stellar-captive-core.cfg" ] && [ -f "/etc/stellar/stellar-captive-core.cfg" ]; then
    echo "Copying stellar-captive-core.cfg from staging..."
    cp /etc/stellar/stellar-captive-core.cfg "$HZHOME/etc/stellar-captive-core.cfg"
    chown stellar:stellar "$HZHOME/etc/stellar-captive-core.cfg"
fi
if [ ! -f "$HZHOME/etc/horizon.env" ] && [ -f "/etc/stellar/horizon.env" ]; then
    echo "Copying horizon.env from staging..."
    cp /etc/stellar/horizon.env "$HZHOME/etc/horizon.env"
    chown stellar:stellar "$HZHOME/etc/horizon.env"
fi

# ============================================================
# 2. Initialize PostgreSQL (if needed)
# ============================================================
if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "First run: initializing PostgreSQL..."
    # SSL workaround (known Docker PostgreSQL bug)
    if [ -d /etc/ssl/private ]; then
        mkdir -p /etc/ssl/private-copy
        cp -r /etc/ssl/private/* /etc/ssl/private-copy/ 2>/dev/null || true
        rm -rf /etc/ssl/private
        mv /etc/ssl/private-copy /etc/ssl/private
        chmod -R 0700 /etc/ssl/private
        chown -R postgres /etc/ssl/private
    fi
    sudo -u postgres $PGBIN/initdb -D "$PGDATA"
    echo "PostgreSQL initialized."
else
    echo "PostgreSQL already initialized."
fi

# ============================================================
# 3. Configure PostgreSQL access
# ============================================================
echo "localhost:5432:*:stellar:$PGPASS" > /root/.pgpass
chmod 0600 /root/.pgpass

# ============================================================
# 4. Start PostgreSQL
# ============================================================
# Uses default PostgreSQL 16 config
if [ -f /etc/postgresql/16/main/postgresql.conf ]; then
    PG_CONFIG="/etc/postgresql/16/main/postgresql.conf"
elif [ -f "$PGHOME/etc/postgresql.conf" ]; then
    PG_CONFIG="$PGHOME/etc/postgresql.conf"
else
    PG_CONFIG="/tmp/postgresql.conf"
    cat > "$PG_CONFIG" << 'CONF'
listen_addresses = 'localhost'
port = 5432
max_connections = 100
shared_buffers = 128MB
dynamic_shared_memory_type = posix
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB
CONF
fi

# Remove stale lock file (from unclean shutdown)
if [ -f "$PGDATA/postmaster.pid" ]; then
    echo "Removing stale PostgreSQL lock file..."
    rm -f "$PGDATA/postmaster.pid"
fi

# Check if PostgreSQL is already running
if sudo -u postgres $PGBIN/pg_isready -h localhost -p $PGPORT &>/dev/null; then
    echo "PostgreSQL is already running."
else
    echo "Starting PostgreSQL..."
    sudo -u postgres $PGBIN/postgres -D "$PGDATA" -c config_file="$PG_CONFIG" &
fi
PGPID=$!

# Wait for PostgreSQL to become available (up to 3 min)
for i in $(seq 1 90); do
    if sudo -u postgres psql -c 'SELECT 1' &>/dev/null; then
        echo "PostgreSQL ready (PID $PGPID)."
        break
    fi
    if [ $((i % 5)) -eq 0 ]; then
        echo "Waiting for PostgreSQL... ($((i*2))s of 180s max)"
    fi
    sleep 2
done

# ============================================================
# 5. Create horizon database and user (if needed)
# ============================================================
if ! sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw horizon; then
    echo "Creating horizon database and user..."
    sudo -u postgres createdb horizon 2>/dev/null || true
    sudo -u postgres psql -c "CREATE USER stellar WITH PASSWORD '$PGPASS' SUPERUSER;" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE horizon TO stellar;" 2>/dev/null || true
    echo "horizon database ready."
fi

# ============================================================
# 6. Finalize horizon.env config with real values
# ============================================================
echo "Configuring horizon.env..."
cat > "$HZHOME/etc/horizon.env" << 'HORIZONEOF'
#!/bin/bash
export DATABASE_URL="postgres://stellar:stellar@localhost/horizon"
export STELLAR_CORE_URL="http://localhost:11726"
export STELLAR_CORE_BINARY_PATH=/usr/bin/stellar-core
export LOG_LEVEL="info"
export ENABLE_CAPTIVE_CORE_INGESTION="true"
export CAPTIVE_CORE_USE_DB=true
export STELLAR_CAPTIVE_CORE_HTTP_PORT=11726
export INGEST="true"
export PER_HOUR_RATE_LIMIT="72000"
export DISABLE_ASSET_STATS="true"
export ADMIN_PORT=6060
export PORT=8001
export CHECKPOINT_FREQUENCY=64
export INGEST_DISABLE_STATE_VERIFICATION=True
export CAPTIVE_CORE_CONFIG_PATH=/opt/stellar/horizon/etc/stellar-captive-core.cfg
export CAPTIVE_CORE_STORAGE_PATH=/opt/stellar/horizon/captive-core
export STELLAR_CORE_VERSION="v27.1.0"
HORIZONEOF
chmod +x "$HZHOME/etc/horizon.env"

# ============================================================
# 7. Run database migrations
# ============================================================
echo "Running Horizon migrations..."
export DATABASE_URL="postgres://stellar:stellar@localhost/horizon"
stellar-horizon db init 2>&1 | tail -5 || echo "Migrations: ok (or already applied)"

# ============================================================
# 8. Start nginx
# ============================================================
echo "Starting nginx on port 8000..."
nginx -g "daemon off;" &
NGINXPID=$!
echo "nginx running (PID $NGINXPID)."

# ============================================================
# 9. Start Horizon (which manages captive core internally)
# ============================================================
echo ""
echo "=== Starting stellar-horizon ==="
echo "Public API:  http://0.0.0.0:8000 (nginx -> 8001)"
echo "PostgreSQL:   localhost:5432"
echo "Captive Core: P2P=11725 HTTP=11726"
echo ""

source "$HZHOME/etc/horizon.env"
echo "Starting stellar-horizon serve..."
exec stellar-horizon serve
