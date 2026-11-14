#!/usr/bin/env bash
# Demonstração ao vivo para o vídeo (enunciado, seção 7.3): cache, N+1, índices e uma rodada curta de k6.
#
# Pré-requisitos: docker compose up -d; API na 8080 iniciada com SQL_LOG_LEVEL=info (./mvnw spring-boot:run);
# psql, jq e k6 no host. Uso: scripts/demo-video.sh   (DEMO_API=http://localhost:8080 para outra API)
# Pausa entre os passos ("Enter para continuar"). Só leitura, exceto o PUT do passo 1, que é revertido
# mesmo se o script for interrompido. Termina sem índice extra, com o Redis vazio e o preço original.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

set -a; . ./.env; set +a
export PGHOST=127.0.0.1 PGPORT=$POSTGRES_PORT PGUSER=$POSTGRES_ADMIN_USER PGDATABASE=$POSTGRES_DB
export PGPASSWORD=$POSTGRES_ADMIN_PASSWORD   # só no ambiente do psql; nunca impressa

API=${DEMO_API:-http://localhost:8080}
PRODUTO=10
TMP=$(mktemp -d)
PRECO_ORIGINAL=""

N=$'\e[0m'; B=$'\e[1m'; D=$'\e[2m'; CIANO=$'\e[36m'; VERDE=$'\e[32m'; AMARELO=$'\e[33m'; VERMELHO=$'\e[31m'

titulo() { printf '\n%s%s══ %s %s\n\n' "$B" "$CIANO" "$1" "$N"; }
info()   { printf '%s%s%s\n' "$D" "$1" "$N"; }
pausa()  { read -r -p $'\n'"${D}Enter para continuar${N}" _ || true; echo; }
ms()     { awk -v s="$1" 'BEGIN { v = sprintf("%.1f", s * 1000); sub(/\./, ",", v); print v }'; }
redis()  { docker compose exec -T redis redis-cli "$@" | tr -d '\r'; }
sql()    { psql -X -At -v ON_ERROR_STOP=1 "$@"; }

# $1 método, $2 caminho, $3 corpo JSON (opcional). Deixa o corpo em $TMP/corpo e imprime uma linha-resumo.
requisicao() {
    local metodo=$1 caminho=$2 corpo=${3:-} saida codigo tempo sqls
    if [ -n "$corpo" ]; then
        saida=$(curl -s -X "$metodo" -H 'Content-Type: application/json' -d "$corpo" -o "$TMP/corpo" \
            -D "$TMP/cabecalho" -w '%{http_code} %{time_total} %{size_download}' "$API$caminho")
    else
        saida=$(curl -s -X "$metodo" -o "$TMP/corpo" -D "$TMP/cabecalho" \
            -w '%{http_code} %{time_total} %{size_download}' "$API$caminho")
    fi
    read -r codigo tempo BYTES <<< "$saida"
    sqls=$(grep -i '^x-sql-count:' "$TMP/cabecalho" | tr -d '\r' | awk '{ print $2 }')
    printf '  %-6s %-46s HTTP %s | %sX-SQL-Count: %-4s%s | %8s ms' \
        "$metodo" "$caminho" "$codigo" "$B" "$sqls" "$N" "$(ms "$tempo")"
}

restaurar_preco() {
    if [ -n "$PRECO_ORIGINAL" ]; then
        corpo=$(jq -c --argjson p "$PRECO_ORIGINAL" '{nome, descricao, preco: $p, ativo}' "$TMP/original.json")
        curl -s -o /dev/null -X PUT -H 'Content-Type: application/json' -d "$corpo" "$API/api/produtos/$PRODUTO"
        PRECO_ORIGINAL=""
    fi
}
trap 'restaurar_preco; rm -rf "$TMP"' EXIT

curl -s -o /dev/null "$API/actuator/health" || { echo "API fora do ar em $API (./mvnw spring-boot:run)."; exit 1; }
sql -q -f db/indice/remover_indice.sql 2> /dev/null   # garante o estado padrão: só pedido_pkey

# ---------------------------------------------------------------------------------------------------------
titulo "1. Cache com Redis: MISS, HIT, TTL e invalidação"
for _ in $(seq 20); do                                       # aquecimento descartado, em outro produto
    curl -s -o /dev/null "$API/api/produtos/20/sem-cache"; curl -s -o /dev/null "$API/api/produtos/20/com-cache"
done
redis FLUSHDB > /dev/null
info "JVM aquecida em outro produto. Redis esvaziado (FLUSHDB). Chaves: $(redis DBSIZE)"
echo
requisicao GET "/api/produtos/$PRODUTO/sem-cache"; echo "   ${D}sem cache: sempre vai ao banco${N}"
cp "$TMP/corpo" "$TMP/original.json"
requisicao GET "/api/produtos/$PRODUTO/com-cache"; echo "   ${AMARELO}MISS${N}: consulta o banco e grava no Redis"
requisicao GET "/api/produtos/$PRODUTO/com-cache"; echo "   ${VERDE}HIT${N}: veio do Redis, nenhum SQL"
echo
info "Chave no Redis: produtos::$PRODUTO | TTL restante: $(redis TTL "produtos::$PRODUTO") s (configurado: 5 min)"
pausa

preco=$(jq -r '.preco' "$TMP/original.json")
novo=$(awk -v p="$preco" 'BEGIN { printf "%.2f", p + 100 }')
PRECO_ORIGINAL=$preco
requisicao PUT "/api/produtos/$PRODUTO" "$(jq -c --argjson p "$novo" '{nome, descricao, preco: $p, ativo}' "$TMP/original.json")"
echo "   preço $preco → $novo"
echo "  ${B}A chave ainda existe no Redis?${N} $( [ "$(redis EXISTS "produtos::$PRODUTO")" = 0 ] && echo "${VERDE}não: o PUT a removeu (@CacheEvict)${N}" || echo "${VERMELHO}sim${N}")"
requisicao GET "/api/produtos/$PRODUTO/com-cache"; echo "   ${AMARELO}MISS${N} com o preço novo: $(jq -r '.preco' "$TMP/corpo")"
requisicao GET "/api/produtos/$PRODUTO/com-cache"; echo "   ${VERDE}HIT${N}: $(jq -r '.preco' "$TMP/corpo")"
restaurar_preco
info "Preço restaurado para $preco."
pausa

# ---------------------------------------------------------------------------------------------------------
titulo "2. LAZY × EAGER × JOIN FETCH × SQL nativo (10 pedidos com cliente e itens)"
for rota in lazy eager join-fetch nativa resumo-lazy resumo-eager; do        # aquecimento descartado
    for _ in 1 2 3; do curl -s -o /dev/null "$API/api/experimentos/pedidos/$rota?limite=10"; done
done
info "JVM aquecida: 3 chamadas descartadas por rota."
echo
for rota in lazy eager join-fetch nativa; do
    requisicao GET "/api/experimentos/pedidos/$rota?limite=10"; echo
done
echo
info "LAZY e EAGER: 1 + 10 (itens) + 10 (clientes) = 21 consultas, o N+1. JOIN FETCH: 2. Nativo: 1."
pausa
echo "  ${B}Grid sem itens (pedido, cliente, valor):${N}"
requisicao GET "/api/experimentos/pedidos/resumo-lazy?limite=10"; echo " | $BYTES bytes"
requisicao GET "/api/experimentos/pedidos/resumo-eager?limite=10"; echo " | $BYTES bytes"
echo
info "Mesma resposta; o EAGER carrega os itens mesmo sem usá-los (10 consultas a mais)."
pausa

# ---------------------------------------------------------------------------------------------------------
CONSULTA="SELECT id, data_pedido, status, valor_total FROM pedido WHERE cliente_id = 1
          ORDER BY data_pedido DESC LIMIT 20"
plano() {
    local arquivo=$TMP/plano
    sql -c "EXPLAIN (ANALYZE, BUFFERS) $CONSULTA" > /dev/null          # aquece
    sql -c "EXPLAIN (ANALYZE, BUFFERS) $CONSULTA" > "$arquivo"
    local varredura ordenacao descartadas
    varredura=$(grep -oE '(Seq Scan|Index Scan using [a-z_]+|Bitmap Heap Scan)' "$arquivo" | head -1)
    ordenacao=$(grep -oE 'Sort Method: [a-zA-Z-]+( [a-zA-Z]+)?' "$arquivo" | head -1 | sed 's/Sort Method: /sim, /' || true)
    descartadas=$(grep -oE 'Rows Removed by Filter: [0-9]+' "$arquivo" | awk '{ print $NF }' || true)
    printf '  Varredura:        %s%s%s\n' "$B" "$varredura" "$N"
    printf '  Sort:             %s\n' "${ordenacao:-${VERDE}não (já lê na ordem do índice)${N}}"
    printf '  Linhas lidas e descartadas pelo filtro: %s\n' "${descartadas:-0}"
    printf '  Páginas lidas:    %s\n' "$(grep -m1 -oE 'shared hit=[0-9]+' "$arquivo" | cut -d= -f2)"
    printf '  Tempo no banco:   %s%s ms%s\n' "$B" "$(grep -oE 'Execution Time: [0-9.]+' "$arquivo" | awk '{ sub(/\./, ",", $3); print $3 }')" "$N"
}

titulo "3. Índice: plano de execução de \"pedidos do cliente 1, mais recentes primeiro\""
info "$(echo "$CONSULTA" | tr -s ' \n' ' ')"
echo
echo "  ${B}${VERMELHO}Sem índice${N} (índices em pedido: $(sql -c "SELECT string_agg(indexname, ', ') FROM pg_indexes WHERE tablename = 'pedido'"))"
plano
pausa
sql -q -f db/indice/criar_indice.sql
echo "  ${B}${VERDE}Com índice${N}: CREATE INDEX idx_pedido_cliente_data ON pedido (cliente_id, data_pedido DESC)"
plano
sql -q -f db/indice/remover_indice.sql 2> /dev/null
echo
info "Índice removido de novo (estado padrão do experimento)."
pausa

# ---------------------------------------------------------------------------------------------------------
carga() {   # $1 rótulo; 5 s de aquecimento descartado antes dos 15 s medidos
    k6 run --quiet -e BASE_URL="$API" -e VUS=50 -e DURACAO=5s k6/indice.js > /dev/null 2>&1
    k6 run --quiet -e BASE_URL="$API" -e VUS=50 -e DURACAO=15s -e ROTULO="$1" k6/indice.js 2>&1 \
        | grep 'VUs=' | sed -E "s/^/  /; s/(p95 [0-9.]+ ms)/${B}\1${N}/; s/([0-9.]+ req\/s)/${B}\1${N}/"
}
titulo "4. Teste de carga com k6: 50 usuários virtuais por 15 s, GET /api/clientes/{1..5}/pedidos"
info "Sem índice: 5 s de aquecimento descartado + 15 s medidos..."
carga "Sem índice"
pausa
sql -q -f db/indice/criar_indice.sql
info "Com índice: 5 s de aquecimento descartado + 15 s medidos..."
carga "Com índice"
sql -q -f db/indice/remover_indice.sql 2> /dev/null
pausa

# ---------------------------------------------------------------------------------------------------------
titulo "Estado final"
redis FLUSHDB > /dev/null
echo "  Índices em pedido: $(sql -c "SELECT string_agg(indexname, ', ') FROM pg_indexes WHERE tablename = 'pedido'")"
echo "  Chaves no Redis:   $(redis DBSIZE)"
curl -s "$API/api/produtos/$PRODUTO/sem-cache" > "$TMP/corpo"
echo "  Preço do produto $PRODUTO: $(jq -r '.preco' "$TMP/corpo")"
