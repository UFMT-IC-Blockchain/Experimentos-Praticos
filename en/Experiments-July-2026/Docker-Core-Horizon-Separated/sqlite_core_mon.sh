#!/usr/bin/env bash
echo "=== SQLite Core: Tables ==="
sqlite3 /opt/stellar/core/stellar.db ".tables"

echo ""
echo "=== SQLite Core: Schema ==="
sqlite3 /opt/stellar/core/stellar.db ".schema"

echo ""
echo "=== SQLite Core: DB Stats ==="
sqlite3 /opt/stellar/core/stellar.db "PRAGMA page_count; PRAGMA page_size; PRAGMA journal_mode;"

echo ""
echo "=== SQLite Core: Row Counts ==="
for tbl in $(sqlite3 /opt/stellar/core/stellar.db ".tables" 2>/dev/null); do
    cnt=$(sqlite3 /opt/stellar/core/stellar.db "SELECT COUNT(*) FROM \"$tbl\";" 2>/dev/null)
    echo "$tbl: $cnt rows"
done

echo ""
echo "=== SQLite Core: File sizes ==="
ls -lh /opt/stellar/core/stellar.db*
