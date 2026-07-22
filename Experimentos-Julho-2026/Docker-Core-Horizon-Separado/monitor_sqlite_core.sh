#!/usr/bin/env bash
# Monitoramento SQLite do Core Node (90 segundos)
OUTDIR="/tmp/sql_monitor"
mkdir -p "$OUTDIR"

echo "=== SQLite CORE: Schema ===" > "$OUTDIR/sqlite_core_schema.txt"
sqlite3 /opt/stellar/core/stellar.db ".tables" >> "$OUTDIR/sqlite_core_schema.txt" 2>&1
echo "" >> "$OUTDIR/sqlite_core_schema.txt"
sqlite3 /opt/stellar/core/stellar.db ".schema" >> "$OUTDIR/sqlite_core_schema.txt" 2>&1

echo "=== SQLite CORE: DB Stats ===" >> "$OUTDIR/sqlite_core_schema.txt"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA page_count; PRAGMA page_size; PRAGMA journal_mode; PRAGMA wal_checkpoint;" >> "$OUTDIR/sqlite_core_schema.txt" 2>&1

echo "=== SQLite CORE: Table Row Counts ===" >> "$OUTDIR/sqlite_core_schema.txt"
for tbl in $(sqlite3 /opt/stellar/core/stellar.db ".tables" 2>/dev/null); do
    cnt=$(sqlite3 /opt/stellar/core/stellar.db "SELECT COUNT(*) FROM \"$tbl\";" 2>/dev/null)
    echo "$tbl: $cnt rows" >> "$OUTDIR/sqlite_core_schema.txt"
done

echo "=== SQLite CORE: Table Sizes ===" >> "$OUTDIR/sqlite_core_schema.txt"
sqlite3 /opt/stellar/core/stellar.db "SELECT name as table_name, (SELECT COUNT(*) FROM \"$name\") as row_count FROM sqlite_master WHERE type='table' ORDER BY name;" 2>/dev/null >> "$OUTDIR/sqlite_core_schema.txt"

echo "=== SQLite CORE: wal checkpoint ===" >> "$OUTDIR/sqlite_core_schema.txt"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA wal_checkpoint(TRUNCATE);" >> "$OUTDIR/sqlite_core_schema.txt" 2>&1
