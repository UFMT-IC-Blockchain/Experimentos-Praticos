#!/usr/bin/env bash
echo "====================================================="
echo " ANALISE COMPLETA DE ARMAZENAMENTO DO CORE VALIDADOR"
echo " Data: $(date -u)"
echo "====================================================="

echo ""
echo ">>> 1. SQLITE PRINCIPAL (stellar.db) <<<"
echo ""

DB="/opt/stellar/core/stellar.db"
MISC="/opt/stellar/core/stellar-misc.db"

echo "--- Configuracao ---"
sqlite3 "$DB" "PRAGMA page_count;" | xargs -I{} echo "Page count: {}"
sqlite3 "$DB" "PRAGMA page_size;" | xargs -I{} echo "Page size: {} bytes"
sqlite3 "$DB" "PRAGMA journal_mode;" | xargs -I{} echo "Journal mode: {}"
sqlite3 "$DB" "PRAGMA synchronous;" | xargs -I{} echo "Synchronous: {}"
sqlite3 "$DB" "PRAGMA auto_vacuum;" | xargs -I{} echo "Auto-vacuum: {}"
sqlite3 "$DB" "PRAGMA cache_size;" | xargs -I{} echo "Cache size: {} pages"
sqlite3 "$DB" "PRAGMA wal_checkpoint;" | xargs -I{} echo "WAL checkpoint: {}"
sqlite3 "$DB" "PRAGMA freelist_count;" | xargs -I{} echo "Freelist pages: {}"
sqlite3 "$DB" "PRAGMA integrity_check;" | xargs -I{} echo "Integrity: {}"
echo "DB File: $(ls -lh "$DB" | awk '{print $5}')"
echo "WAL File: $(ls -lh "${DB}-wal" 2>/dev/null | awk '{print $5}')"

echo ""
echo "--- Schema ---"
sqlite3 "$DB" ".schema"

echo ""
echo "--- Tabelas ---"
for tbl in $(sqlite3 "$DB" ".tables"); do
    echo ""
    echo "Tabela: $tbl"
    echo "  Colunas:"
    sqlite3 "$DB" "PRAGMA table_info($tbl);" | awk -F'|' '{print "    - " $2 ": " $3 " (pk=" $6 ")"}'
    echo "  Indices:"
    sqlite3 "$DB" "PRAGMA index_list($tbl);" | awk -F'|' '{print "    - " $2 " (unique=" $3 ")"}'
    for idx in $(sqlite3 "$DB" "PRAGMA index_list($tbl);" | awk -F'|' '{print $2}'); do
        sqlite3 "$DB" "PRAGMA index_info($idx);" | awk -F'|' '{print "      -> coluna " $3}'
    done
    cnt=$(sqlite3 "$DB" "SELECT COUNT(*) FROM \"$tbl\";")
    echo "  Total rows: $cnt"
done

echo ""
echo "--- Storestate Details ---"
sqlite3 -header "$DB" "SELECT statename, length(state) as bytes, substr(state,1,60) as preview FROM storestate;"

echo ""
echo "--- Offers Amostra (5 linhas) ---"
sqlite3 -header "$DB" "SELECT sellerid, offerid, sellingasset, buyingasset, amount, price, lastmodified FROM offers LIMIT 5;"

echo ""
echo "--- Offers Estatisticas ---"
sqlite3 "$DB" "SELECT COUNT(*) as total FROM offers;" | xargs -I{} echo "Total offers: {}"
sqlite3 "$DB" "SELECT COUNT(DISTINCT sellerid) FROM offers;" | xargs -I{} echo "Sellers unicos: {}"
sqlite3 "$DB" "SELECT MIN(lastmodified) FROM offers;" | xargs -I{} echo "Min ledger: {}"
sqlite3 "$DB" "SELECT MAX(lastmodified) FROM offers;" | xargs -I{} echo "Max ledger: {}"
sqlite3 "$DB" "SELECT COUNT(DISTINCT sellingasset) FROM offers;" | xargs -I{} echo "Ativos venda unicos: {}"
sqlite3 "$DB" "SELECT COUNT(DISTINCT buyingasset) FROM offers;" | xargs -I{} echo "Ativos compra unicos: {}"

echo ""
echo "====================================================="
echo ">>> 2. SQLITE MISC (stellar-misc.db) <<<"
echo ""

echo "--- Configuracao ---"
sqlite3 "$MISC" "PRAGMA page_count;" | xargs -I{} echo "Page count: {}"
sqlite3 "$MISC" "PRAGMA page_size;" | xargs -I{} echo "Page size: {} bytes"
sqlite3 "$MISC" "PRAGMA journal_mode;" | xargs -I{} echo "Journal mode: {}"
sqlite3 "$MISC" "PRAGMA synchronous;" | xargs -I{} echo "Synchronous: {}"
echo "DB File: $(ls -lh "$MISC" | awk '{print $5}')"
echo "WAL File: $(ls -lh "${MISC}-wal" 2>/dev/null | awk '{print $5}')"

echo ""
echo "--- Schema ---"
sqlite3 "$MISC" ".schema"

echo ""
echo "--- Conteudo ---"
for tbl in $(sqlite3 "$MISC" ".tables"); do
    echo "Tabela: $tbl"
    cnt=$(sqlite3 "$MISC" "SELECT COUNT(*) FROM \"$tbl\";")
    echo "  Total rows: $cnt"
    sqlite3 "$MISC" "PRAGMA table_info($tbl);" | awk -F'|' '{print "  - " $2 ": " $3}'
    echo "  Dados:"
    sqlite3 -header "$MISC" "SELECT * FROM \"$tbl\" LIMIT 10;"
done

echo ""
echo "====================================================="
echo ">>> 3. BUCKETS (.xdr) <<<"
echo ""

echo "--- Estatisticas Gerais ---"
BUCKETDIR="/opt/stellar/core/buckets"
echo "Total buckets XDR: $(ls "$BUCKETDIR"/*.xdr 2>/dev/null | wc -l)"
echo "Total buckets INDEX: $(ls "$BUCKETDIR"/*.index 2>/dev/null | wc -l)"
echo "Tamanho total: $(du -sh "$BUCKETDIR" 2>/dev/null | awk '{print $1}')"

echo ""
echo "--- Top 10 Maiores Buckets ---"
ls -lhS "$BUCKETDIR"/*.xdr 2>/dev/null | head -10 | awk '{print "  " $5 " - " $NF}'

echo ""
echo "--- Distribuicao por Tamanho ---"
echo "  >= 500 MB: $(ls -l "$BUCKETDIR"/*.xdr 2>/dev/null | awk '$5 >= 500000000' | wc -l) arquivos"
echo "  100-500 MB: $(ls -l "$BUCKETDIR"/*.xdr 2>/dev/null | awk '$5 >= 100000000 && $5 < 500000000' | wc -l) arquivos"
echo "  10-100 MB: $(ls -l "$BUCKETDIR"/*.xdr 2>/dev/null | awk '$5 >= 10000000 && $5 < 100000000' | wc -l) arquivos"
echo "  1-10 MB: $(ls -l "$BUCKETDIR"/*.xdr 2>/dev/null | awk '$5 >= 1000000 && $5 < 10000000' | wc -l) arquivos"
echo "  < 1 MB: $(ls -l "$BUCKETDIR"/*.xdr 2>/dev/null | awk '$5 < 1000000' | wc -l) arquivos"

echo ""
echo "--- Buckets por Data de Criacao ---"
ls -l "$BUCKETDIR"/*.xdr 2>/dev/null | awk '{print $6, $7, $8}' | sort | uniq -c | sort -rn | head -10

echo ""
echo "--- Conteudo dos Buckets (do /metrics se disponivel) ---"
curl -s http://localhost:11626/info 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)['info']
print('  Ledger:', d['ledger']['num'])
print('  State:', d['state'])
print('  Peers:', d['peers']['authenticated_count'])
print('  Protocol:', d['protocol_version'])
" 2>/dev/null || echo "  (indisponivel)"

echo ""
echo "====================================================="
echo ">>> 4. CHECKPOINTS (arquivos temporarios) <<<"
echo ""

echo "Arquivos de checkpoint em tmp:"
find "$BUCKETDIR/tmp" -name '*.xdr' 2>/dev/null | head -10
echo ""
echo "Total arquivos temporarios: $(find "$BUCKETDIR/tmp" -type f 2>/dev/null | wc -l)"
echo "Tamanho tmp: $(du -sh "$BUCKETDIR/tmp" 2>/dev/null | awk '{print $1}')"

echo ""
echo "====================================================="
echo ">>> 5. RESUMO COMPARATIVO DOS 3 SISTEMAS <<<"
echo ""

echo "SISTEMA        | TAMANHO  | CONTEUDO              | FUNCAO"
echo "---------------+----------+-----------------------+-----------------------------"
echo "SQLite (main)  | 23 MB DB | offers (56.6K)       | Cache do estado atual"
echo "               | 42 MB WAL| storestate (5)        | para validacao SCP"
echo "---------------+----------+-----------------------+-----------------------------"
echo "SQLite (misc)  | ~200 KB  | peers, quorum,        | Metadados operacionais"
echo "               | ~8 MB WAL| ledger info           | (rede, peers, config)"
echo "---------------+----------+-----------------------+-----------------------------"
echo "Buckets (.xdr) | ~5.7 GB  | accounts (2,9M)       | Estado COMPLETO do ledger"
echo "               |          | trustlines (325K)     | (snapshots imutaveis)"
echo "               |          | contract data (4,2M)  |"
echo "               |          | offers, etc           |"
echo "---------------+----------+-----------------------+-----------------------------"
echo "TOTAL          | ~5.8 GB  | -                     | -"
echo ""

echo "====================================================="
echo " OBSERVACAO IMPORTANTE:"
echo " NAO ha PostgreSQL rodando no container do core."
echo " O core usa APENAS SQLite + Buckets XDR."
echo " PostgreSQL existe no container do Horizon (API)."
echo "====================================================="
