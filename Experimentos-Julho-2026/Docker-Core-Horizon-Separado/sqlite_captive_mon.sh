#!/usr/bin/env bash
echo "=== SQLite Captive: Row Counts ==="
for tbl in $(sqlite3 /opt/stellar/horizon/captive-core/stellar.db ".tables"); do
    cnt=$(sqlite3 /opt/stellar/horizon/captive-core/stellar.db "SELECT COUNT(*) FROM \"$tbl\";")
    echo "$tbl: $cnt rows"
done

echo ""
echo "=== SQLite Captive: File sizes ==="
ls -lh /opt/stellar/horizon/captive-core/stellar.db*

echo ""
echo "=== PostgreSQL WAL size ==="
psql -h localhost -U stellar -d horizon -c "SELECT count(*) as wal_files, pg_size_pretty(sum(size)) as wal_size FROM pg_ls_waldir();" 2>/dev/null

echo ""
echo "=== PostgreSQL DB size ==="
psql -h localhost -U stellar -d horizon -c "SELECT pg_size_pretty(pg_database_size('horizon')) as db_size;"

echo ""
echo "=== PostgreSQL key_value_store ==="
psql -h localhost -U stellar -d horizon -c "SELECT * FROM key_value_store;"

echo ""
echo "=== Current ingest progress ==="
psql -h localhost -U stellar -d horizon -c "SELECT MAX(ledger_seq) as max_ledger FROM history_ledgers;" 2>/dev/null

echo ""
echo "=== Ledger processing rate ==="
psql -h localhost -U stellar -d horizon -c "SELECT COUNT(*) as ledgers_90s FROM history_ledgers WHERE closed_at > NOW() - INTERVAL '90 seconds';"
