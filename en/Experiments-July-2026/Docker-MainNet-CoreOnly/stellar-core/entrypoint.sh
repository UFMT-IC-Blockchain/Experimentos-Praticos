#!/usr/bin/env bash
set -e

export STELLAR_HOME="/opt/stellar"
export COREHOME="$STELLAR_HOME/core"
export CORELOG="/var/log/stellar-core"
export CONFIG_STAGING="/etc/stellar/stellar-core.cfg"
export CONFIG_TARGET="$COREHOME/etc/stellar-core.cfg"

echo "=== Stellar Core Node (MainNet) - Initializing ==="
echo "Version: $(stellar-core version 2>/dev/null | head -1)"
echo "Network: Public Global Stellar Network ; September 2015"

# Ensures directories
mkdir -p "$CORELOG" "$COREHOME/etc" "$COREHOME/buckets"
chown -R stellar:stellar "$COREHOME" "$CORELOG"

# If the config does not exist on the volume (first run), copy from staging
if [ ! -f "$CONFIG_TARGET" ] && [ -f "$CONFIG_STAGING" ]; then
    echo "Copying configuration from staging to the volume..."
    cp "$CONFIG_STAGING" "$CONFIG_TARGET"
    chown stellar:stellar "$CONFIG_TARGET"
fi

cd "$COREHOME"

# If the SQLite database does not exist, initialize it
if [ ! -f "$COREHOME/stellar.db" ]; then
    echo "First run: initializing Core database..."
    sudo -u stellar stellar-core new-db --conf "$CONFIG_TARGET"
    echo "Initializing history..."
    sudo -u stellar stellar-core new-hist vs --conf "$CONFIG_TARGET"
    echo "Core initialized successfully."
else
    echo "Existing database found. Skipping initialization."
fi

echo "=== Starting stellar-core (validator) ==="
echo "P2P:  11625"
echo "HTTP: 11626"
echo "DB:   sqlite3://$COREHOME/stellar.db"
echo "Workdir: $(pwd)"
echo "Config: $CONFIG_TARGET"
echo ""

exec sudo -u stellar stellar-core --conf "$CONFIG_TARGET" run
