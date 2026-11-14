#!/usr/bin/env bash
# Experimento de índices (enunciado, seção 5): sem índice -> índice simples -> índice composto -> sem índice.
#
# Para cada estado: planos EXPLAIN (ANALYZE, BUFFERS) das consultas de db/indice/explain_pedidos_cliente.sql
# para os clientes 1 (225 pedidos) e 545 (9 pedidos), mediana do Execution Time no banco, tempo na API
# (GET /api/clientes/{id}/pedidos), idx_scan e custo de inserção. Termina sem índice (estado reproduzível).
#
# Pré-requisitos: docker compose up -d; psql e jq no host; porta livre para a API (PORTA_EXPERIMENTO, padrão 18080).
# Uso: scripts/experimento-indice.sh
# Saídas: resultados/indice/indice.csv, resultados/indice/indice.txt, resultados/explain/*.txt
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

set -a; . ./.env; set +a
# DDL e EXPLAIN como admin (o pedidos_app não tem DDL). A senha vai só no ambiente do psql.
export PGHOST=127.0.0.1 PGPORT=$POSTGRES_PORT PGUSER=$POSTGRES_ADMIN_USER PGDATABASE=$POSTGRES_DB
export PGPASSWORD=$POSTGRES_ADMIN_PASSWORD

PORTA=${PORTA_EXPERIMENTO:-18080}
BASE=http://localhost:$PORTA
DIR=resultados/indice
DIR_PLANOS=resultados/explain
CSV=$DIR/indice.csv
TXT=$DIR/indice.txt
CLIENTES=(1 545)
CONSULTAS=(A_pagina0 A_pagina2 B_sem_limite C_intervalo)
AQUECIMENTO_BANCO=3
EXECUCOES_BANCO=10
AQUECIMENTO_API=3
REQUISICOES_API=20
EXECUCOES_INSERCAO=5
TMP=$(mktemp -d)
API_PID=""
FALHAS=0

parar_api() {
    if [ -n "$API_PID" ]; then
        kill "$API_PID" 2>/dev/null || true
        wait "$API_PID" 2>/dev/null || true
        API_PID=""
    fi
}
trap 'parar_api; rm -rf "$TMP"' EXIT

sql() { psql -X -At -v ON_ERROR_STOP=1 "$@"; }

confere() {
    if [ "$2" = "$3" ]; then
        printf '  [OK]     %s = %s\n' "$1" "$2"
    else
        printf '  [FALHOU] %s = %s (esperado %s)\n' "$1" "$2" "$3"
        FALHAS=$((FALHAS + 1))
    fi
}

mediana() {
    sort -n | awk '{ v[NR] = $1 } END {
        if (NR % 2) print v[(NR + 1) / 2]; else printf "%.3f\n", (v[NR / 2] + v[NR / 2 + 1]) / 2 }'
}

p95() { sort -n | awk '{ v[NR] = $1 } END { i = int(NR * 0.95); if (i < NR * 0.95) i++; print v[i] }'; }

indices_pedido() { sql -c "SELECT string_agg(indexname, ',' ORDER BY indexname) FROM pg_indexes WHERE tablename = 'pedido'"; }

idx_scan() { sql -c "SELECT coalesce(sum(idx_scan), 0) FROM pg_stat_user_indexes WHERE indexrelname = '$1'"; }

# $1 = consulta, $2 = cliente, $3 = repetições: executa o bloco EXPLAIN várias vezes numa só sessão.
explain() {
    for _ in $(seq "$3"); do cat "$TMP/$1.sql"; echo; done | sql -v cliente="$2" -f -
}

iniciar_api() {
    if ss -ltn | grep -q ":$PORTA "; then
        echo "A porta $PORTA já está em uso; defina outra com PORTA_EXPERIMENTO=<porta>."
        exit 1
    fi
    SQL_LOG_LEVEL=info SERVER_PORT=$PORTA java -jar "$JAR" > "$TMP/api.log" 2>&1 &
    API_PID=$!
    for _ in $(seq 1 90); do
        curl -s -o /dev/null "$BASE/actuator/health" && return 0
        sleep 1
    done
    echo "A API não subiu."
    exit 1
}

# Extrai do plano salvo: varredura, índice usado, sort, linhas do nó de varredura, linhas removidas,
# buffers do nó raiz e tempo de execução.
analisar_plano() {
    local f=$1 linha
    # "|| true": nem todo plano tem índice, Sort, filtro ou leitura de disco.
    linha=$(grep -m1 -E 'Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan' "$f" || true)
    VARREDURA=$(grep -oE 'Parallel Seq Scan|Seq Scan|Index Only Scan Backward|Index Only Scan|Index Scan Backward|Index Scan|Bitmap Heap Scan' <<< "$linha" | head -1 || true)
    INDICE=$(grep -oE '(using|Bitmap Index Scan on) [a-z_]+' "$f" | head -1 | awk '{ print $NF }' || true)
    SORT=$(grep -oE 'Sort Method: (top-N heapsort|quicksort|external merge)' "$f" | head -1 | sed 's/Sort Method: //' || true)
    LINHAS=$(grep -oE 'actual time=[0-9.]+\.\.[0-9.]+ rows=[0-9.]+' <<< "$linha" | sed 's/.*rows=//' || true)
    REMOVIDAS=$(grep -m1 -oE 'Rows Removed by Filter: [0-9]+' "$f" | awk '{ print $NF }' || true)
    HIT=$(grep -m1 'Buffers:' "$f" | grep -oE 'hit=[0-9]+' | cut -d= -f2 || true)
    READ=$(grep -m1 'Buffers:' "$f" | grep -oE 'read=[0-9]+' | cut -d= -f2 || true)
    INDICE=${INDICE:--}; SORT=${SORT:-nenhum}; REMOVIDAS=${REMOVIDAS:-0}; HIT=${HIT:-0}; READ=${READ:-0}
}

# $1 = cliente, $2 = página: preenche API_MEDIANA, API_P95 e API_SQL.
medir_api() {
    local url="$BASE/api/clientes/$1/pedidos?page=$2&size=20" status tempo
    for _ in $(seq "$AQUECIMENTO_API"); do curl -s -o /dev/null "$url"; done
    : > "$TMP/tempos_api"
    for _ in $(seq "$REQUISICOES_API"); do
        read -r status tempo < <(curl -s -D "$TMP/h" -o /dev/null -w '%{http_code} %{time_total}\n' "$url")
        [ "$status" = 200 ] || { echo "HTTP $status em $url"; exit 1; }
        awk -v t="$tempo" 'BEGIN { printf "%.2f\n", t * 1000 }' >> "$TMP/tempos_api"
    done
    API_SQL=$(grep -i '^x-sql-count' "$TMP/h" | tr -d '\r' | awk '{ print $2 }')
    API_MEDIANA=$(mediana < "$TMP/tempos_api")
    API_P95=$(p95 < "$TMP/tempos_api")
}

# $1 = estado, $2 = índice em teste (ou vazio): planos, tempos no banco e na API, idx_scan.
medir_estado() {
    local estado=$1 indice=$2 cliente consulta plano mediana_banco antes depois pagina
    echo "--- Estado: $estado"
    echo "  Índices em pedido (pg_indexes): $(indices_pedido)"
    printf '  %-13s %-7s %-17s %-24s %-15s %6s %8s %10s %12s %12s %10s %4s\n' consulta cliente varredura indice \
        sort linhas removidas hit/read banco_ms api_ms api_p95 sql
    for cliente in "${CLIENTES[@]}"; do
        for consulta in "${CONSULTAS[@]}"; do
            explain "$consulta" "$cliente" "$AQUECIMENTO_BANCO" > /dev/null
            plano=$DIR_PLANOS/${estado}_${consulta}_cliente${cliente}.txt
            {
                echo "-- estado: $estado | índices em pedido: $(indices_pedido)"
                echo "-- consulta: $consulta | cliente: $cliente | após $AQUECIMENTO_BANCO execuções de aquecimento"
                explain "$consulta" "$cliente" 1
            } > "$plano"
            analisar_plano "$plano"
            mediana_banco=$(explain "$consulta" "$cliente" "$EXECUCOES_BANCO" \
                | grep -oE 'Execution Time: [0-9.]+' | awk '{ print $3 }' | mediana)
            API_MEDIANA=-; API_P95=-; API_SQL=-
            case $consulta in
                A_pagina0) medir_api "$cliente" 0 ;;
                A_pagina2) medir_api "$cliente" 2 ;;
            esac
            echo "$estado,$consulta,$cliente,$VARREDURA,$INDICE,$SORT,$LINHAS,$REMOVIDAS,$HIT,$READ,$mediana_banco,$API_MEDIANA,$API_P95,$API_SQL" >> "$CSV"
            printf '  %-13s %-7s %-17s %-24s %-15s %6s %8s %10s %12s %12s %10s %4s\n' "$consulta" "$cliente" \
                "$VARREDURA" "$INDICE" "$SORT" "$LINHAS" "$REMOVIDAS" "$HIT/$READ" "$mediana_banco" \
                "$API_MEDIANA" "$API_P95" "$API_SQL"
        done
    done

    if [ -n "$indice" ]; then
        # Os backends da aplicação publicam estatísticas com atraso de até ~10 s quando ociosos;
        # espera assentar para que o "antes" já inclua as medições acima.
        sleep 11
        antes=$(idx_scan "$indice")
        for cliente in "${CLIENTES[@]}"; do
            for pagina in 0 2; do curl -s -o /dev/null "$BASE/api/clientes/$cliente/pedidos?page=$pagina&size=20"; done
        done
        for _ in $(seq 1 20); do
            depois=$(idx_scan "$indice")
            [ "$depois" -ge $((antes + 4)) ] && break
            sleep 1
        done
        printf '  idx_scan de %s: %s antes -> %s depois de 4 chamadas à API\n' "$indice" "$antes" "$depois"
        confere "aumento do idx_scan (1 por chamada à API)" "$((depois - antes))" 4
    fi
}

# Custo de escrita: 10.000 pedidos sintéticos com ids explícitos (não consome a sequência), revertidos.
# O ROLLBACK deixa linhas e entradas de índice mortas; o VACUUM depois de cada execução as remove, para
# que a próxima não pague a checagem de unicidade contra elas nem encontre a tabela inchada.
custo_insercao() {
    local tempos
    tempos=$(for _ in $(seq "$EXECUCOES_INSERCAO"); do
        sql <<'SQL' | grep -oE '^(Time: [0-9.]+|wal=[0-9]+)' | sed 's/Time: //' | paste -sd' '
BEGIN;
SELECT pg_current_wal_insert_lsn() AS lsn_inicio \gset
\timing on
INSERT INTO pedido (id, cliente_id, data_pedido, status, valor_total)
SELECT 1000000 + g, 1 + (g % 10000), timestamp '2026-01-01' + g * interval '1 minute', 'PENDENTE', 10.00
FROM generate_series(1, 10000) g;
\timing off
SELECT 'wal=' || pg_wal_lsn_diff(pg_current_wal_insert_lsn(), :'lsn_inicio');
ROLLBACK;
SQL
        sql -q -c 'VACUUM pedido'
    done)
    # Cada linha: "<tempo_ms> wal=<bytes>". O WAL gerado é determinístico e mostra a escrita extra
    # de cada índice, que no tempo fica abaixo da variação entre execuções.
    INSERCAO_MEDIANA=$(awk '{ print $1 }' <<< "$tempos" | mediana)
    INSERCAO_WAL=$(awk '{ sub("wal=", "", $2); print $2 }' <<< "$tempos" | mediana)
    printf '  Inserção de 10.000 pedidos (BEGIN ... ROLLBACK), %s execuções: %s ms -> mediana %s ms | WAL gerado %s KB\n' \
        "$EXECUCOES_INSERCAO" "$(awk '{ print $1 }' <<< "$tempos" | paste -sd' ')" "$INSERCAO_MEDIANA" \
        "$(awk -v b="$INSERCAO_WAL" 'BEGIN { printf "%.0f", b / 1024 }')"
    echo "$1,$INSERCAO_MEDIANA,$INSERCAO_WAL" >> "$TMP/insercao.csv"
    confere "pedidos após o ROLLBACK" "$(sql -c 'SELECT count(*) FROM pedido')" 100000
}

tamanho() {
    printf '  Tamanho: tabela pedido %s | %s %s | pedido_pkey %s\n' \
        "$(sql -c "SELECT pg_size_pretty(pg_relation_size('pedido'))")" "$1" \
        "$(sql -c "SELECT pg_size_pretty(pg_relation_size('$1'))")" \
        "$(sql -c "SELECT pg_size_pretty(pg_relation_size('pedido_pkey'))")"
}

# Planos (sem custos) das consultas da Etapa 6, para confirmar que o índice não as afeta.
planos_etapa6() {
    sql > "$DIR_PLANOS/etapa6_$1.txt" <<'SQL'
\echo '-- lazy/eager/join-fetch: lista de pedidos'
EXPLAIN (COSTS OFF) select p1_0.id, p1_0.cliente_id, p1_0.data_pedido, p1_0.status, p1_0.valor_total
from pedido p1_0 order by p1_0.id fetch first 100 rows only;
\echo '-- lazy/eager: itens de um pedido (N+1)'
EXPLAIN (COSTS OFF) select i1_0.pedido_id, i1_0.id, i1_0.preco_unitario, i1_0.produto_id, i1_0.quantidade
from item_pedido i1_0 where i1_0.pedido_id = 1;
\echo '-- nativa'
EXPLAIN (COSTS OFF) SELECT p.id, p.data_pedido, p.status, p.valor_total, c.nome AS cliente_nome,
       i.produto_id, i.quantidade, i.preco_unitario
FROM (SELECT * FROM pedido ORDER BY id LIMIT 100) p
JOIN cliente c ON c.id = p.cliente_id
JOIN item_pedido i ON i.pedido_id = p.id
ORDER BY p.id, i.id;
SQL
}

mkdir -p "$DIR" "$DIR_PLANOS"
awk -v dir="$TMP" '/^-- consulta: / { nome = $3; next } nome { print > (dir "/" nome ".sql") }' \
    db/indice/explain_pedidos_cliente.sql
echo "Empacotando a aplicação..."
./mvnw -q -DskipTests package
JAR=$(ls target/trabalho-a2-*.jar | grep -v plain | head -1)

exec > >(tee "$TXT") 2>&1
echo "=== Experimento de índices — $(date '+%Y-%m-%d %H:%M:%S')"
echo "Base: $(sql -c "SELECT count(*) FROM pedido") pedidos; cliente 1 = 225 pedidos, cliente 545 = 9 pedidos."
echo "Banco: mediana do Execution Time de $EXECUCOES_BANCO EXPLAIN ANALYZE após $AQUECIMENTO_BANCO de aquecimento."
echo "API: GET /api/clientes/{id}/pedidos?page={0|2}&size=20, $AQUECIMENTO_API aquecimentos + $REQUISICOES_API medidas (curl time_total)."
echo "Linhas = linhas devolvidas pelo nó de varredura; removidas = Rows Removed by Filter; hit/read = buffers do nó raiz."
echo

echo "estado,consulta,cliente,varredura,indice,sort,linhas_varredura,linhas_removidas,buffers_hit,buffers_read,mediana_banco_ms,mediana_api_ms,p95_api_ms,sql_count_api" > "$CSV"
: > "$TMP/insercao.csv"

sql -q -f db/indice/remover_indice.sql
sql -q -f db/indice/remover_indice_simples.sql
iniciar_api
echo "--- Aquecimento geral da API (descartado)"
for _ in $(seq 50); do
    for cliente in "${CLIENTES[@]}"; do
        for pagina in 0 2; do curl -s -o /dev/null "$BASE/api/clientes/$cliente/pedidos?page=$pagina&size=20"; done
    done
done
echo

medir_estado sem ""
custo_insercao sem
planos_etapa6 sem
echo

sql -q -f db/indice/criar_indice_simples.sql
medir_estado simples idx_pedido_cliente
tamanho idx_pedido_cliente
custo_insercao simples
sql -q -f db/indice/remover_indice_simples.sql
echo

sql -q -f db/indice/criar_indice.sql
medir_estado composto idx_pedido_cliente_data
tamanho idx_pedido_cliente_data
custo_insercao composto
planos_etapa6 composto

echo "  Etapa 6 com o índice composto (limite=100):"
confere "planos das consultas da Etapa 6 iguais aos sem índice" \
    "$(diff -q "$DIR_PLANOS/etapa6_sem.txt" "$DIR_PLANOS/etapa6_composto.txt" > /dev/null && echo sim || echo nao)" sim
PORTA_EXPERIMENTO=$((PORTA + 10)) LIMITES_EXPERIMENTO=100 DIR_SAIDA="$TMP/persistencia" PULAR_EMPACOTAMENTO=1 \
    scripts/experimento-persistencia.sh > "$TMP/persistencia.log" 2>&1 || true
confere "SQLs por estratégia (limite=100) iguais aos da Etapa 6" \
    "$(diff -q <(grep ',100,' resultados/persistencia/persistencia.csv | cut -d, -f1,3) \
               <(grep ',100,' "$TMP/persistencia/persistencia.csv" | cut -d, -f1,3) > /dev/null && echo sim || echo nao)" sim
grep ',100,' "$TMP/persistencia/persistencia.csv" | cut -d, -f1,3 | paste -sd' ' | sed 's/^/    estrategia,sqls: /'
echo

sql -q -f db/indice/remover_indice.sql
# Controle: o mesmo estado "sem" medido de novo, na mesma JVM já aquecida pelos estados anteriores.
# Separa o efeito do índice do efeito do aquecimento da JVM no tempo da API.
medir_estado sem_final ""
parar_api
echo

# Reescreve tabela e índices: devolve o tamanho físico da carga original (as inserções revertidas
# deixaram páginas livres no pedido_pkey) e atualiza o visibility map e as estatísticas.
sql -q -c 'VACUUM FULL pedido' -c 'VACUUM ANALYZE pedido'
echo "--- Estado final"
printf '  Tamanho: tabela pedido %s | pedido_pkey %s\n' "$(sql -c "SELECT pg_size_pretty(pg_relation_size('pedido'))")" \
    "$(sql -c "SELECT pg_size_pretty(pg_relation_size('pedido_pkey'))")"
confere "índices em pedido" "$(indices_pedido)" pedido_pkey
confere "pedidos" "$(sql -c 'SELECT count(*) FROM pedido')" 100000
echo
echo "--- Custo de inserção (mediana de $EXECUCOES_INSERCAO, 10.000 pedidos)"
awk -F, '{ printf "  %-9s tempo %8s ms | WAL %6.0f KB\n", $1 ":", $2, $3 / 1024 }' "$TMP/insercao.csv"
echo
echo "=== Verificações com falha: $FALHAS"
exit "$FALHAS"
