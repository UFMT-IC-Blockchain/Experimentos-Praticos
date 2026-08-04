#!/usr/bin/env bash
set -e

export STELLAR_HOME="/opt/stellar"
export COREHOME="$STELLAR_HOME/core"
export CORELOG="/var/log/stellar-core"
export CONFIG_STAGING="/etc/stellar/stellar-core.cfg"
export CONFIG_TARGET="$COREHOME/etc/stellar-core.cfg"

echo "=== Stellar Core Node (MainNet) - Inicializando ==="
echo "Versao: $(stellar-core version 2>/dev/null | head -1)"
echo "Network: Public Global Stellar Network ; September 2015"

# Garante diretorios
mkdir -p "$CORELOG" "$COREHOME/etc" "$COREHOME/buckets"
chown -R stellar:stellar "$COREHOME" "$CORELOG"

# Se a config nao existe no volume (primeira exec), copia do staging
if [ ! -f "$CONFIG_TARGET" ] && [ -f "$CONFIG_STAGING" ]; then
    echo "Copiando configuracao do staging para o volume..."
    cp "$CONFIG_STAGING" "$CONFIG_TARGET"
    chown stellar:stellar "$CONFIG_TARGET"
fi

cd "$COREHOME"

# Se o banco SQLite nao existe, inicializa
if [ ! -f "$COREHOME/stellar.db" ]; then
    echo "Primeira execucao: inicializando banco do Core..."
    sudo -u stellar stellar-core new-db --conf "$CONFIG_TARGET"
    echo "Inicializando historico..."
    sudo -u stellar stellar-core new-hist vs --conf "$CONFIG_TARGET"
    echo "Core inicializado com sucesso."
else
    echo "Banco existente encontrado. Pulando inicializacao."
fi

echo "=== Iniciando stellar-core (validador) ==="
echo "P2P:  11625"
echo "HTTP: 11626"
echo "DB:   sqlite3://$COREHOME/stellar.db"
echo "Workdir: $(pwd)"
echo "Config: $CONFIG_TARGET"
echo ""

exec sudo -u stellar stellar-core --conf "$CONFIG_TARGET" run
