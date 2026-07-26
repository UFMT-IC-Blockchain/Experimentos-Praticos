#!/usr/bin/env bash
set -e

OUTDIR="/tmp/db_analysis"
mkdir -p "$OUTDIR"

echo "=========================================="
echo " ANALISE DOS BANCOS DE DADOS STELLAR"
echo " Data: $(date -u)"
echo "=========================================="

# ============================================
# 1. SQLITE DO CORE
# ============================================
echo ""
echo ">>> SQLITE CORE NODE"
echo ""

sqlite3 /opt/stellar/core/stellar.db "PRAGMA page_count;" > "$OUTDIR/core_page_count"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA page_size;" > "$OUTDIR/core_page_size"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA journal_mode;" > "$OUTDIR/core_journal"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA wal_checkpoint;" > "$OUTDIR/core_wal_checkpoint"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA cache_size;" > "$OUTDIR/core_cache"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA synchronous;" > "$OUTDIR/core_sync"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA auto_vacuum;" > "$OUTDIR/core_autovac"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA mmap_size;" > "$OUTDIR/core_mmap"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA page_checksum;" > "$OUTDIR/core_checksum"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA locking_mode;" > "$OUTDIR/core_locking"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA temp_store;" > "$OUTDIR/core_temp"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA application_id;" > "$OUTDIR/core_appid"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA user_version;" > "$OUTDIR/core_userversion"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA freelist_count;" > "$OUTDIR/core_freelist"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA schema_version;" > "$OUTDIR/core_schemaversion"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA integrity_check;" > "$OUTDIR/core_integrity"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA quick_check;" > "$OUTDIR/core_quickcheck"

echo "--- Core SQLite Config ---"
cat "$OUTDIR/core_page_count" | while read val; do echo "Page count: $val"; done
cat "$OUTDIR/core_page_size" | while read val; do echo "Page size: $val bytes"; done
echo "Total size: $(($(cat "$OUTDIR/core_page_count") * $(cat "$OUTDIR/core_page_size"))) bytes"
echo "Journal mode: $(cat "$OUTDIR/core_journal")"
echo "Synchronous: $(cat "$OUTDIR/core_sync") (1=FULL, 2=NORMAL)"
echo "Auto-vacuum: $(cat "$OUTDIR/core_autovac") (0=NONE)"
echo "Cache size: $(cat "$OUTDIR/core_cache") pages"
echo "MMAP size: $(cat "$OUTDIR/core_mmap") bytes"
echo "Integrity: $(cat "$OUTDIR/core_integrity")"
echo ""

echo "--- Core Tables ---"
for tbl in $(sqlite3 /opt/stellar/core/stellar.db ".tables"); do
    echo ""
    echo "Table: $tbl"
    echo "  Columns:"
    sqlite3 /opt/stellar/core/stellar.db "PRAGMA table_info($tbl);" | while IFS='|' read cid name type notnull dflt pk; do
        echo "    - $name: $type${pk:+ PRIMARY KEY}"
    done
    echo "  Indexes:"
    sqlite3 /opt/stellar/core/stellar.db "PRAGMA index_list($tbl);" | while IFS='|' read seq name unique origin partial; do
        echo "    - $name (unique=$unique)"
        sqlite3 /opt/stellar/core/stellar.db "PRAGMA index_info($name);" | while IFS='|' read seqno cid colname; do
            echo "      -> $colname"
        done
    done
    cnt=$(sqlite3 /opt/stellar/core/stellar.db "SELECT COUNT(*) FROM \"$tbl\";")
    echo "  Row count: $cnt"
    # Estimate avg row size
    dbpages=$(cat "$OUTDIR/core_page_count")
    dbsize=$((dbpages * $(cat "$OUTDIR/core_page_size")))
    # Rough estimate: assume offers is the main table
    if [ "$tbl" = "offers" ] && [ "$cnt" -gt 0 ]; then
        echo "  Estimated avg row: $((dbsize / cnt)) bytes"
    fi
done

echo ""
echo "--- Core Storestate ---"
sqlite3 -header /opt/stellar/core/stellar.db "SELECT statename, length(state) as state_bytes FROM storestate;"

echo ""
echo "--- Core Offers Stats ---"
sqlite3 -header /opt/stellar/core/stellar.db "SELECT COUNT(*) as total_offers, AVG(amount) as avg_amount, MIN(lastmodified) as min_ledger, MAX(lastmodified) as max_ledger, COUNT(DISTINCT sellerid) as unique_sellers FROM offers;"

echo ""
echo "--- Core File Sizes ---"
ls -lh /opt/stellar/core/stellar.db*

echo ""
echo "--- Core DB Total Disk Usage ---"
du -sh /opt/stellar/core/

# ============================================
# 2. SQLITE DO CAPTIVE CORE
# ============================================
echo ""
echo "=========================================="
echo ">>> SQLITE CAPTIVE CORE (Horizon)"
echo "=========================================="

CAPTIVE_DB="/opt/stellar/horizon/captive-core/stellar.db"

if [ -f "$CAPTIVE_DB" ]; then
    echo "Captive DB found at $CAPTIVE_DB"
    
    sqlite3 "$CAPTIVE_DB" "PRAGMA page_count;" > "$OUTDIR/captive_page_count"
    sqlite3 "$CAPTIVE_DB" "PRAGMA page_size;" > "$OUTDIR/captive_page_size"
    sqlite3 "$CAPTIVE_DB" "PRAGMA journal_mode;" > "$OUTDIR/captive_journal"
    sqlite3 "$CAPTIVE_DB" "PRAGMA wal_checkpoint;" > "$OUTDIR/captive_wal"
    sqlite3 "$CAPTIVE_DB" "PRAGMA synchronous;" > "$OUTDIR/captive_sync"
    sqlite3 "$CAPTIVE_DB" "PRAGMA auto_vacuum;" > "$OUTDIR/captive_autovac"
    sqlite3 "$CAPTIVE_DB" "PRAGMA integrity_check;" > "$OUTDIR/captive_integrity"
    
    echo "Page count: $(cat "$OUTDIR/captive_page_count")"
    echo "Page size: $(cat "$OUTDIR/captive_page_size") bytes"
    echo "Total size: $(($(cat "$OUTDIR/captive_page_count") * $(cat "$OUTDIR/captive_page_size"))) bytes"
    echo "Journal: $(cat "$OUTDIR/captive_journal")"
    echo "Synchronous: $(cat "$OUTDIR/captive_sync")"
    echo "Auto-vacuum: $(cat "$OUTDIR/captive_autovac")"
    echo "Integrity: $(cat "$OUTDIR/captive_integrity")"
    
    echo ""
    echo "--- Captive Tables ---"
    for tbl in $(sqlite3 "$CAPTIVE_DB" ".tables"); do
        cnt=$(sqlite3 "$CAPTIVE_DB" "SELECT COUNT(*) FROM \"$tbl\";")
        echo "$tbl: $cnt rows"
    done
    
    echo ""
    echo "--- Captive File Sizes ---"
    ls -lh "$CAPTIVE_DB"*
else
    echo "Captive DB NOT FOUND at $CAPTIVE_DB"
fi

# ============================================
# 3. POSTGRESQL
# ============================================
echo ""
echo "=========================================="
echo ">>> POSTGRESQL (Horizon)"
echo "=========================================="

if pg_isready -h localhost -p 5432 &>/dev/null; then
    echo "PostgreSQL is running."
    
    echo ""
    echo "--- DB Size ---"
    psql -h localhost -U stellar -d horizon -c "SELECT pg_size_pretty(pg_database_size('horizon')) as db_size;"
    
    echo ""
    echo "--- Top 10 Largest Tables ---"
    psql -h localhost -U stellar -d horizon -c "
    SELECT
        relname as table_name,
        pg_size_pretty(pg_total_relation_size(relid)) as total_size,
        pg_size_pretty(pg_table_size(relid)) as data_size,
        pg_size_pretty(pg_indexes_size(relid)) as index_size,
        reltuples::bigint as row_estimate
    FROM pg_catalog.pg_statio_user_tables
    ORDER BY pg_total_relation_size(relid) DESC
    LIMIT 15;
    "
    
    echo ""
    echo "--- Table Row Counts ---"
    psql -h localhost -U stellar -d horizon -c "
    SELECT schemaname||'.'||tablename as table_name, n_live_tup as rows
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
    ORDER BY n_live_tup DESC;
    "
    
    echo ""
    echo "--- Key Value Store (Ingest State) ---"
    psql -h localhost -U stellar -d horizon -c "SELECT * FROM key_value_store;"
    
    echo ""
    echo "--- WAL Size ---"
    psql -h localhost -U stellar -d horizon -c "SELECT count(*) as wal_files, pg_size_pretty(sum(size)) as wal_size FROM pg_ls_waldir();"
    
    echo ""
    echo "--- Table Bloat Estimate ---"
    psql -h localhost -U stellar -d horizon -c "
    SELECT
        schemaname||'.'||tablename as tbl,
        n_dead_tup as dead_rows,
        n_live_tup as live_rows,
        round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 1) as dead_pct
    FROM pg_stat_user_tables
    WHERE n_dead_tup > 0 AND schemaname = 'public'
    ORDER BY n_dead_tup DESC
    LIMIT 10;
    "
    
    echo ""
    echo "--- Index Stats ---"
    psql -h localhost -U stellar -d horizon -c "
    SELECT
        schemaname||'.'||indexrelname as idx,
        idx_scan as scans,
        idx_tup_read as tuples_read,
        idx_tup_fetch as tuples_fetched,
        pg_size_pretty(pg_relation_size(indexrelid)) as idx_size
    FROM pg_stat_user_indexes
    ORDER BY idx_scan DESC
    LIMIT 15;
    "
    
    echo ""
    echo "--- Cache Hit Ratio ---"
    psql -h localhost -U stellar -d horizon -c "
    SELECT
        'cache hit ratio' as metric,
        round(sum(blks_hit)::numeric / NULLIF(sum(blks_hit + blks_read), 0) * 100, 2) as pct
    FROM pg_stat_database
    WHERE datname = 'horizon';
    "
    
    echo ""
    echo "--- Checkpoint Stats ---"
    psql -h localhost -U stellar -d horizon -c "
    SELECT checkpoints_timed, checkpoints_req, buffers_checkpoint, buffers_clean, buffers_backend
    FROM pg_stat_bgwriter;
    "
else
    echo "PostgreSQL is NOT running. Skipping PG analysis."
fi

echo ""
echo "=========================================="
echo " ANALISE CONCLUIDA"
echo "=========================================="
