#!/usr/bin/env bash
# Monitoring SQL queries in all databases for 90 seconds
# Executed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

OUTDIR="/tmp/sql_monitor"
mkdir -p "$OUTDIR"

echo "=========================================="
echo "START OF SQL MONITORING (90 seconds)"
echo "Date: $(date -u)"
echo "=========================================="

# =========================================================
# SNAPSHOT 1: BEFORE (baseline)
# =========================================================

echo "[1/5] Collecting snapshot BEFORE..."

# PostgreSQL - pg_stat_statements
echo "=== PG: pg_stat_statements BEFORE ===" > "$OUTDIR/pg_statements_before.sql"
psql -h localhost -U stellar -d horizon -c "
SELECT
    queryid,
    LEFT(query, 120) as query_preview,
    calls,
    total_exec_time::numeric(10,1) as total_ms,
    rows,
    mean_exec_time::numeric(10,1) as avg_ms,
    shared_blks_hit + shared_blks_read as blocks_accessed,
    shared_blks_written as blocks_written
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY total_exec_time DESC
LIMIT 40;
" >> "$OUTDIR/pg_statements_before.sql" 2>&1

# PostgreSQL - pg_stat_user_tables
echo "=== PG: pg_stat_user_tables BEFORE ===" > "$OUTDIR/pg_tables_before.sql"
psql -h localhost -U stellar -d horizon -c "
SELECT
    schemaname||'.'||relname as table_name,
    seq_scan, seq_tup_read,
    idx_scan, idx_tup_fetch,
    n_tup_ins, n_tup_upd, n_tup_del,
    n_tup_hot_upd,
    n_live_tup, n_dead_tup,
    pg_size_pretty(pg_total_relation_size(relid)) as total_size
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_tup_ins DESC;
" >> "$OUTDIR/pg_tables_before.sql" 2>&1

# PostgreSQL - pg_stat_activity (active queries)
echo "=== PG: pg_stat_activity BEFORE ===" > "$OUTDIR/pg_activity_before.sql"
psql -h localhost -U stellar -d horizon -c "
SELECT
    pid,
    state,
    usename,
    wait_event_type,
    wait_event,
    LEFT(query, 150) as query,
    query_start,
    state_change,
    backend_type
FROM pg_stat_activity
WHERE state != 'idle'
  AND backend_type != 'autovacuum worker'
ORDER BY query_start;
" >> "$OUTDIR/pg_activity_before.sql" 2>&1

# PostgreSQL - locks
echo "=== PG: Locks BEFORE ===" > "$OUTDIR/pg_locks_before.sql"
psql -h localhost -U stellar -d horizon -c "
SELECT
    locktype,
    relation::regclass as relation_name,
    mode,
    granted,
    pid,
    virtualxid as vxid,
    transactionid as txid,
    virtualtransaction as vtx
FROM pg_locks
WHERE NOT pid IN (SELECT pid FROM pg_stat_activity WHERE backend_type = 'autovacuum worker')
ORDER BY locktype, mode;
" >> "$OUTDIR/pg_locks_before.sql" 2>&1

# PostgreSQL - bgwriter
echo "=== PG: BgWriter BEFORE ===" > "$OUTDIR/pg_bgwriter_before.sql"
psql -h localhost -U stellar -d horizon -c "
SELECT
    checkpoints_timed, checkpoints_req,
    buffers_checkpoint, buffers_clean, buffers_backend,
    buffers_alloc,
    maxwritten_clean,
    buffers_backend_fsync
FROM pg_stat_bgwriter;
" >> "$OUTDIR/pg_bgwriter_before.sql" 2>&1

echo "Snapshot BEFORE collected."

# =========================================================
# ACTIVE MONITORING (every 5 seconds for 90s)
# =========================================================

echo "[2/5] Starting sampling every 5s for 90s..."
echo "" > "$OUTDIR/pg_activity_samples.sql"

for i in $(seq 1 18); do
    sleep 5
    
    # Sample unix timestamp
    TS=$(date -u +"%H:%M:%S")
    
    echo "--- Sample $i / 18 (T=${TS}) ---" >> "$OUTDIR/pg_activity_samples.sql"
    
    # PostgreSQL active queries
    psql -h localhost -U stellar -d horizon -t -c "
    SELECT '$TS' as sample_time, pid, state,
           wait_event_type, wait_event,
           LEFT(LEFT(query, 80), 75) as query_short,
           EXTRACT(EPOCH FROM (now() - query_start))::int as running_s
    FROM pg_stat_activity
    WHERE state != 'idle'
      AND backend_type != 'autovacuum worker'
      AND pid != pg_backend_pid()
    ORDER BY query_start;
    " >> "$OUTDIR/pg_activity_samples.sql" 2>&1
    
    # Write-Ahead Log stats
    psql -h localhost -U stellar -d horizon -t -c "
    SELECT '$TS' as t,
           (SELECT COUNT(*) FROM pg_ls_waldir())::int as wal_files,
           (SELECT SUM(size) FROM pg_ls_waldir())::numeric(20,0) as wal_bytes;
    " >> "$OUTDIR/pg_wal_samples.sql" 2>/dev/null || true
done

echo "Sampling completed."

# =========================================================
# SNAPSHOT 2: AFTER (after 90s)
# =========================================================

echo "[3/5] Collecting snapshot AFTER..."

# PostgreSQL - pg_stat_statements AFTER
echo "=== PG: pg_stat_statements AFTER ===" > "$OUTDIR/pg_statements_after.sql"
psql -h localhost -U stellar -d horizon -c "
SELECT
    queryid,
    LEFT(query, 120) as query_preview,
    calls,
    total_exec_time::numeric(10,1) as total_ms,
    rows,
    mean_exec_time::numeric(10,1) as avg_ms,
    shared_blks_hit + shared_blks_read as blocks_accessed,
    shared_blks_written as blocks_written,
    local_blks_written
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY total_exec_time DESC
LIMIT 40;
" >> "$OUTDIR/pg_statements_after.sql" 2>&1

# PostgreSQL - pg_stat_user_tables AFTER
echo "=== PG: pg_stat_user_tables AFTER ===" > "$OUTDIR/pg_tables_after.sql"
psql -h localhost -U stellar -d horizon -c "
SELECT
    schemaname||'.'||relname as table_name,
    seq_scan, seq_tup_read,
    idx_scan, idx_tup_fetch,
    n_tup_ins, n_tup_upd, n_tup_del,
    n_tup_hot_upd,
    n_live_tup, n_dead_tup,
    pg_size_pretty(pg_total_relation_size(relid)) as total_size
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_tup_ins DESC;
" >> "$OUTDIR/pg_tables_after.sql" 2>&1

# PostgreSQL - pg_stat_activity AFTER
echo "=== PG: pg_stat_activity AFTER ===" > "$OUTDIR/pg_activity_after.sql"
psql -h localhost -U stellar -d horizon -c "
SELECT
    pid, state, usename,
    wait_event_type, wait_event,
    LEFT(query, 150) as query,
    query_start, state_change,
    backend_type
FROM pg_stat_activity
WHERE state != 'idle'
  AND backend_type != 'autovacuum worker'
ORDER BY query_start;
" >> "$OUTDIR/pg_activity_after.sql" 2>&1

# PostgreSQL - bgwriter AFTER
echo "=== PG: BgWriter AFTER ===" > "$OUTDIR/pg_bgwriter_after.sql"
psql -h localhost -U stellar -d horizon -c "
SELECT
    checkpoints_timed, checkpoints_req,
    buffers_checkpoint, buffers_clean, buffers_backend,
    buffers_alloc,
    maxwritten_clean,
    buffers_backend_fsync
FROM pg_stat_bgwriter;
" >> "$OUTDIR/pg_bgwriter_after.sql" 2>&1

echo "Snapshot AFTER collected."

# =========================================================
# SQLITE: schema and statistics
# =========================================================

echo "[4/5] Collecting data from the SQLites..."

# Core SQLite schema
echo "=== SQLite Core: Schema ===" > "$OUTDIR/sqlite_core_schema.txt"
sqlite3 /opt/stellar/core/stellar.db ".schema" >> "$OUTDIR/sqlite_core_schema.txt" 2>&1

echo "=== SQLite Core: Tables Row Count ===" >> "$OUTDIR/sqlite_core_schema.txt"
sqlite3 /opt/stellar/core/stellar.db "SELECT name as tbl, (
    SELECT COUNT(*) FROM \"$name\" WHERE 1=1
) as row_count FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;" 2>/dev/null >> "$OUTDIR/sqlite_core_schema.txt"

echo "=== SQLite Core: Table Names ===" >> "$OUTDIR/sqlite_core_schema.txt"
sqlite3 /opt/stellar/core/stellar.db ".tables" >> "$OUTDIR/sqlite_core_schema.txt" 2>&1

echo "=== SQLite Core: Database Stats ===" >> "$OUTDIR/sqlite_core_schema.txt"
sqlite3 /opt/stellar/core/stellar.db "PRAGMA page_count; PRAGMA page_size; PRAGMA journal_mode; PRAGMA wal_checkpoint;" >> "$OUTDIR/sqlite_core_schema.txt" 2>&1

# Captive SQLite schema
echo "=== SQLite Captive: Schema ===" > "$OUTDIR/sqlite_captive_schema.txt"
CAPTIVE_DB="/opt/stellar/horizon/captive-core/stellar.db"
sqlite3 "$CAPTIVE_DB" ".schema" >> "$OUTDIR/sqlite_captive_schema.txt" 2>&1

echo "=== SQLite Captive: Tables ===" >> "$OUTDIR/sqlite_captive_schema.txt"
sqlite3 "$CAPTIVE_DB" ".tables" >> "$OUTDIR/sqlite_captive_schema.txt" 2>&1

echo "=== SQLite Captive: DB Stats ===" >> "$OUTDIR/sqlite_captive_schema.txt"
sqlite3 "$CAPTIVE_DB" "PRAGMA page_count; PRAGMA page_size; PRAGMA journal_mode; PRAGMA wal_checkpoint;" >> "$OUTDIR/sqlite_captive_schema.txt" 2>&1

echo "SQLite data collected."

# =========================================================
# SUMMARY
# =========================================================

echo "[5/5] Generating summary..."
echo ""
echo "=========================================="
echo "MONITORING SUMMARY"
echo "=========================================="

echo ""
echo "--- PostgreSQL Table Statistics ---"
psql -h localhost -U stellar -d horizon -c "
SELECT 'Tables with most inserts' as type;
SELECT
    schemaname||'.'||relname as tbl,
    n_tup_ins - lag_n_tup_ins as d_ins,
    n_tup_upd - lag_n_tup_upd as d_upd,
    n_tup_del - lag_n_tup_del as d_del,
    n_live_tup as live_rows
FROM (
    SELECT *,
        lag(n_tup_ins) OVER (PARTITION BY relid ORDER BY now()) as lag_n_tup_ins,
        lag(n_tup_upd) OVER (PARTITION BY relid ORDER BY now()) as lag_n_tup_upd,
        lag(n_tup_del) OVER (PARTITION BY relid ORDER BY now()) as lag_n_tup_del
    FROM pg_stat_user_tables
) sub
WHERE schemaname = 'public'
ORDER BY d_ins DESC NULLS LAST
LIMIT 15;
" 2>/dev/null || echo "(delta not available - first reading)"

echo ""
echo "--- Top 10 Queries by Total Time ---"
psql -h localhost -U stellar -d horizon -c "
SELECT
    LEFT(query, 90) as query,
    calls,
    round(total_exec_time::numeric, 1) as total_ms,
    round(mean_exec_time::numeric, 1) as avg_ms,
    rows,
    round(rows/NULLIF(calls,0)::numeric, 1) as rows_per_call,
    round(shared_blks_hit::numeric/NULLIF(shared_blks_hit + shared_blks_read, 0)*100, 1) as cache_hit_pct
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
  AND query NOT LIKE '%pg_settings%'
ORDER BY total_exec_time DESC
LIMIT 15;
" 2>/dev/null || echo "(pg_stat_statements empty)"

echo ""
echo "--- Distribution by Command Type ---"
psql -h localhost -U stellar -d horizon -c "
SELECT
    CASE
        WHEN query ~* '^SELECT' THEN 'SELECT'
        WHEN query ~* '^INSERT' THEN 'INSERT'
        WHEN query ~* '^UPDATE' THEN 'UPDATE'
        WHEN query ~* '^DELETE' THEN 'DELETE'
        WHEN query ~* '^COPY' THEN 'COPY'
        WHEN query ~* '^CREATE' THEN 'CREATE'
        WHEN query ~* '^ALTER' THEN 'ALTER'
        WHEN query ~* '^DROP' THEN 'DROP'
        WHEN query ~* '^TRUNCATE' THEN 'TRUNCATE'
        WHEN query ~* '^BEGIN' THEN 'BEGIN'
        WHEN query ~* '^COMMIT' THEN 'COMMIT'
        WHEN query ~* '^ROLLBACK' THEN 'ROLLBACK'
        WHEN query ~* '^SAVEPOINT' THEN 'SAVEPOINT'
        WHEN query ~* '^RELEASE' THEN 'RELEASE'
        ELSE 'OTHER'
    END as cmd_type,
    COUNT(*) as query_count,
    SUM(calls) as total_calls,
    round(SUM(total_exec_time)::numeric, 1) as total_time_ms,
    round(SUM(rows)::numeric, 0) as total_rows
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
  AND query NOT LIKE '%pg_settings%'
  AND query NOT LIKE '%pg_ls_waldir%'
GROUP BY cmd_type
ORDER BY total_time_ms DESC;
" 2>/dev/null || echo "(pg_stat_statements empty)"

echo ""
echo "=========================================="
echo "END OF MONITORING"
echo "Date: $(date -u)"
echo "=========================================="
