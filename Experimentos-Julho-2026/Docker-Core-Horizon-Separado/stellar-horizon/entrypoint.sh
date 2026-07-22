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

echo "=== Stellar Horizon - Inicializando ==="
echo "Versao Core: $(stellar-core version 2>/dev/null | head -1)"
echo "Versao Horizon: $(stellar-horizon version 2>/dev/null | head -1)"
echo "Network: Test SDF Network ; September 2015"

# ============================================================
# 1. Preparar diretorios e configs
# ============================================================
mkdir -p "$HZHOME/etc" "$HZHOME/captive-core" "$PGDATA" /var/run/postgresql
chown -R stellar:stellar "$HZHOME" 2>/dev/null || true
chown -R postgres:postgres "$PGDATA" /var/run/postgresql 2>/dev/null || true

# Corrige permissoes SSL (bug PostgreSQL em container)
chown root:root /etc/ssl/private 2>/dev/null || true
chmod 0711 /etc/ssl/private 2>/dev/null || true
find /etc/ssl/private -type f -exec chmod 0640 {} \; 2>/dev/null || true

# Copia configs do staging se nao existirem no volume
if [ ! -f "$HZHOME/etc/stellar-captive-core.cfg" ] && [ -f "/etc/stellar/stellar-captive-core.cfg" ]; then
    echo "Copiando stellar-captive-core.cfg do staging..."
    cp /etc/stellar/stellar-captive-core.cfg "$HZHOME/etc/stellar-captive-core.cfg"
    chown stellar:stellar "$HZHOME/etc/stellar-captive-core.cfg"
fi
if [ ! -f "$HZHOME/etc/horizon.env" ] && [ -f "/etc/stellar/horizon.env" ]; then
    echo "Copiando horizon.env do staging..."
    cp /etc/stellar/horizon.env "$HZHOME/etc/horizon.env"
    chown stellar:stellar "$HZHOME/etc/horizon.env"
fi

# ============================================================
# 2. Inicializar PostgreSQL (se necessario)
# ============================================================
if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "Primeira execucao: inicializando PostgreSQL..."
    # Workaround SSL (bug conhecido do Docker PostgreSQL)
    if [ -d /etc/ssl/private ]; then
        mkdir -p /etc/ssl/private-copy
        cp -r /etc/ssl/private/* /etc/ssl/private-copy/ 2>/dev/null || true
        rm -rf /etc/ssl/private
        mv /etc/ssl/private-copy /etc/ssl/private
        chmod -R 0700 /etc/ssl/private
        chown -R postgres /etc/ssl/private
    fi
    sudo -u postgres $PGBIN/initdb -D "$PGDATA"
    echo "PostgreSQL inicializado."
else
    echo "PostgreSQL ja inicializado."
fi

# ============================================================
# 3. Configurar acesso ao PostgreSQL
# ============================================================
echo "localhost:5432:*:stellar:$PGPASS" > /root/.pgpass
chmod 0600 /root/.pgpass

# ============================================================
# 4. Iniciar PostgreSQL
# ============================================================
# Usa config padrao do PostgreSQL 16
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

# Remove stale lock file (de shutdown nao limpo)
if [ -f "$PGDATA/postmaster.pid" ]; then
    echo "Removendo lock file stale do PostgreSQL..."
    rm -f "$PGDATA/postmaster.pid"
fi

# Verifica se PostgreSQL ja esta rodando
if sudo -u postgres $PGBIN/pg_isready -h localhost -p $PGPORT &>/dev/null; then
    echo "PostgreSQL ja esta rodando."
else
    echo "Iniciando PostgreSQL..."
    sudo -u postgres $PGBIN/postgres -D "$PGDATA" -c config_file="$PG_CONFIG" &
fi
PGPID=$!

# Aguarda PostgreSQL ficar disponivel (ate 3 min)
for i in $(seq 1 90); do
    if sudo -u postgres psql -c 'SELECT 1' &>/dev/null; then
        echo "PostgreSQL pronto (PID $PGPID)."
        break
    fi
    if [ $((i % 5)) -eq 0 ]; then
        echo "Aguardando PostgreSQL... ($((i*2))s de 180s max)"
    fi
    sleep 2
done

# ============================================================
# 5. Criar banco horizon e usuario (se necessario)
# ============================================================
if ! sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw horizon; then
    echo "Criando banco horizon e usuario..."
    sudo -u postgres createdb horizon 2>/dev/null || true
    sudo -u postgres psql -c "CREATE USER stellar WITH PASSWORD '$PGPASS' SUPERUSER;" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE horizon TO stellar;" 2>/dev/null || true
    echo "Banco horizon pronto."
fi

# ============================================================
# 6. Finalizar config do horizon.env com valores reais
# ============================================================
echo "Configurando horizon.env..."
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
# 7. Executar migracoes do banco
# ============================================================
echo "Executando migracoes do Horizon..."
export DATABASE_URL="postgres://stellar:stellar@localhost/horizon"
stellar-horizon db init 2>&1 | tail -5 || echo "Migracoes: ok (ou ja aplicadas)"

# ============================================================
# 8. Iniciar nginx
# ============================================================
echo "Iniciando nginx na porta 8000..."
nginx -g "daemon off;" &
NGINXPID=$!
echo "nginx rodando (PID $NGINXPID)."

# ============================================================
# 9. Iniciar Horizon (que gerencia captive core internamente)
# ============================================================
echo ""
echo "=== Iniciando stellar-horizon ==="
echo "API publica:  http://0.0.0.0:8000 (nginx -> 8001)"
echo "PostgreSQL:   localhost:5432"
echo "Captive Core: P2P=11725 HTTP=11726"
echo ""

source "$HZHOME/etc/horizon.env"
echo "Iniciando stellar-horizon serve..."
exec stellar-horizon serve
