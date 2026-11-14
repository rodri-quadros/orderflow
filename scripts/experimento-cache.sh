#!/usr/bin/env bash
# Experimento obrigatório do cache (enunciado, seção 3.4) e comparação sequencial (seção 3.5).
#
# Pré-requisitos:
#   docker compose up -d
#   CACHE_TTL_PRODUTOS=10s SQL_LOG_LEVEL=info ./mvnw spring-boot:run   # TTL curto para o passo 6
# Uso:
#   scripts/experimento-cache.sh [id_produto]      (padrão: 10)
# Saída: resultados/cache/experimento-cache.txt
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

set -a; . ./.env; set +a   # apenas para as variáveis do Compose; nenhuma senha é impressa
API=http://localhost:8080
ID=${1:-10}
CHAVE="produtos::$ID"
N_COMPARACAO=200
SAIDA=resultados/cache/experimento-cache.txt
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FALHAS=0

mkdir -p resultados/cache
exec > >(tee "$SAIDA") 2>&1

# REDISCLI_AUTH já está no ambiente do container, então a senha não aparece na linha de comando.
redis() { docker compose exec -T redis redis-cli --raw "$@"; }

metrica() {
    local v
    v=$(curl -s "$API/actuator/metrics/cache.gets?tag=cache:produtos&tag=result:$1" \
        | grep -oE '"value":[0-9.E]+' | head -1 | cut -d: -f2)
    printf '%.0f' "${v:-0}"
}

# Executa uma requisição e preenche STATUS, SQL, TEMPO_MS e CORPO.
req() {
    local metodo=$1 rota=$2 corpo=${3:-} tempo
    local args=(-s -X "$metodo" -D "$TMP/h" -o "$TMP/b" -w '%{http_code} %{time_total}\n')
    [ -n "$corpo" ] && args+=(-H 'Content-Type: application/json' -d "$corpo")
    read -r STATUS tempo < <(curl "${args[@]}" "$API$rota")
    SQL=$(grep -i '^x-sql-count' "$TMP/h" | tr -d '\r' | awk '{print $2}')
    TEMPO_MS=$(awk -v t="$tempo" 'BEGIN { printf "%.1f", t * 1000 }')
    CORPO=$(cat "$TMP/b")
}

mostra() {
    printf '  %-5s %-32s -> HTTP %s | X-SQL-Count: %s | tempo: %6s ms\n' "$1" "$2" "$STATUS" "$SQL" "$TEMPO_MS"
    printf '        corpo: %s\n' "$CORPO"
}

estado() {
    printf '  Redis: EXISTS %s = %s | TTL = %s s | GET = %s\n' \
        "$CHAVE" "$(redis EXISTS "$CHAVE")" "$(redis TTL "$CHAVE")" "$(redis GET "$CHAVE")"
    printf '  Actuator cache.gets (acumulado): hit=%s miss=%s\n' "$(metrica hit)" "$(metrica miss)"
}

confere() {
    if [ "$2" = "$3" ]; then
        printf '  [OK]     %s = %s\n' "$1" "$2"
    else
        printf '  [FALHOU] %s = %s (esperado %s)\n' "$1" "$2" "$3"
        FALHAS=$((FALHAS + 1))
    fi
}

preco() { grep -oE '"preco":[0-9.]+' <<< "$1" | cut -d: -f2; }

# SQL como admin dentro do container (autenticação local), sem expor senha.
sql_admin() { docker compose exec -T postgres psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -Atc "$1"; }

# Compara byte a byte o corpo de /com-cache (deve ser HIT) com o de /sem-cache (banco).
compara_bytes() {
    curl -s -o "$TMP/hit.json" "$API/api/produtos/$1/com-cache"
    curl -s -o "$TMP/banco.json" "$API/api/produtos/$1/sem-cache"
    printf '  cmp com-cache (%s bytes) x sem-cache (%s bytes)\n' "$(wc -c < "$TMP/hit.json")" "$(wc -c < "$TMP/banco.json")"
    confere "corpo do cache idêntico byte a byte ao do banco" \
        "$(cmp -s "$TMP/hit.json" "$TMP/banco.json" && echo sim || echo nao)" sim
}

# Imprime média, p50, p95 e máximo de uma lista de tempos (um por linha).
estatisticas() {
    sort -n "$1" | awk '{ v[NR] = $1; s += $1 } END {
        p50 = v[int(NR * 0.50 + 0.999)]; p95 = v[int(NR * 0.95 + 0.999)]
        printf "média %6.2f ms | p50 %6.2f ms | p95 %6.2f ms | máx %6.2f ms", s / NR, p50, p95, v[NR] }'
}

# Faz GET em /api/produtos/1..N/<variante> e resume tempos e SQLs.
rodada() {
    local variante=$1 rotulo=$2 total_sql=0
    : > "$TMP/tempos"
    for i in $(seq 1 "$N_COMPARACAO"); do
        req GET "/api/produtos/$i/$variante"
        echo "$TEMPO_MS" >> "$TMP/tempos"
        total_sql=$((total_sql + SQL))
    done
    printf '  %-26s %s | SQLs: %d em %d requisições\n' "$rotulo" "$(estatisticas "$TMP/tempos")" "$total_sql" "$N_COMPARACAO"
}

if ! curl -s -o /dev/null "$API/actuator/health"; then
    echo "API fora do ar. Inicie com: CACHE_TTL_PRODUTOS=10s SQL_LOG_LEVEL=info ./mvnw spring-boot:run"
    exit 1
fi

echo "=== Experimento de cache — $(date '+%Y-%m-%d %H:%M:%S') — produto $ID"
echo "Banco: $(sql_admin "SELECT count(*) || ' produtos, ' || (SELECT count(*) FROM pedido) || ' pedidos' FROM produto")"
echo

echo "--- Passo 0: estado inicial conhecido (FLUSHDB)"
redis FLUSHDB > /dev/null
estado
echo

echo "--- Passo 1: cenário A, sem cache (2 consultas seguidas)"
for vez in 1 2; do
    req GET "/api/produtos/$ID/sem-cache"; mostra GET "/api/produtos/$ID/sem-cache"
    confere "X-SQL-Count (consulta $vez)" "$SQL" 1
done
estado
confere "EXISTS (sem-cache não grava no cache)" "$(redis EXISTS "$CHAVE")" 0
echo

echo "--- Passo 2: cenário B, cache vazio -> MISS"
req GET "/api/produtos/$ID/com-cache"; mostra GET "/api/produtos/$ID/com-cache"
CORPO_ORIGINAL=$CORPO
TTL_CONFIGURADO=$(redis TTL "$CHAVE")
confere "X-SQL-Count (MISS)" "$SQL" 1
confere "EXISTS (chave criada)" "$(redis EXISTS "$CHAVE")" 1
estado
echo

echo "--- Passo 3: cenário B de novo -> HIT"
req GET "/api/produtos/$ID/com-cache"; mostra GET "/api/produtos/$ID/com-cache"
confere "X-SQL-Count (HIT)" "$SQL" 0
confere "corpo igual ao do passo 2" "$([ "$CORPO" = "$CORPO_ORIGINAL" ] && echo sim || echo nao)" sim
compara_bytes "$ID"
estado
echo

PRECO_ORIGINAL=$(preco "$CORPO_ORIGINAL")
PRECO_NOVO=$(awk -v p="$PRECO_ORIGINAL" 'BEGIN { printf "%.2f", p + 100 }')
echo "--- Passo 4: PUT alterando o preço de $PRECO_ORIGINAL para $PRECO_NOVO -> invalidação"
req PUT "/api/produtos/$ID" "$(sed -E "s/\"preco\":[0-9.]+/\"preco\":$PRECO_NOVO/" <<< "$CORPO_ORIGINAL")"
mostra PUT "/api/produtos/$ID"
confere "HTTP do PUT" "$STATUS" 200
confere "EXISTS (chave removida pelo @CacheEvict)" "$(redis EXISTS "$CHAVE")" 0
estado
echo

echo "--- Passo 5: consulta após a alteração -> MISS com preço novo, depois HIT"
req GET "/api/produtos/$ID/com-cache"; mostra GET "/api/produtos/$ID/com-cache"
confere "X-SQL-Count (MISS após invalidação)" "$SQL" 1
confere "preço retornado" "$(preco "$CORPO")" "$PRECO_NOVO"
req GET "/api/produtos/$ID/com-cache"; mostra GET "/api/produtos/$ID/com-cache"
confere "X-SQL-Count (HIT)" "$SQL" 0
confere "preço retornado" "$(preco "$CORPO")" "$PRECO_NOVO"
estado
echo

echo "--- Passo 6: expiração por TTL (TTL configurado: ${TTL_CONFIGURADO}s)"
if [ "$TTL_CONFIGURADO" -le 60 ]; then
    while [ "$(redis EXISTS "$CHAVE")" = 1 ]; do
        printf '  aguardando expiração... TTL restante = %s s\n' "$(redis TTL "$CHAVE")"
        sleep 2
    done
    confere "EXISTS (expirou sem nenhuma escrita)" "$(redis EXISTS "$CHAVE")" 0
    req GET "/api/produtos/$ID/com-cache"; mostra GET "/api/produtos/$ID/com-cache"
    confere "X-SQL-Count (MISS por expiração)" "$SQL" 1
    estado
else
    echo "  PULADO: TTL de ${TTL_CONFIGURADO}s é longo demais para aguardar."
    echo "  Reinicie a API com CACHE_TTL_PRODUTOS=10s e rode o script de novo."
fi
echo

PRECO_FORA=$(awk -v p="$PRECO_ORIGINAL" 'BEGIN { printf "%.2f", p + 200 }')
echo "--- Passo 7: risco de dado desatualizado (escrita direto no banco, sem passar pela API)"
redis DEL "$CHAVE" > /dev/null
req GET "/api/produtos/$ID/com-cache"; mostra GET "/api/produtos/$ID/com-cache"
PRECO_EM_CACHE=$(preco "$CORPO")
echo "  UPDATE produto SET preco = $PRECO_FORA WHERE id = $ID   (fora da aplicação: nenhum @CacheEvict é disparado)"
sql_admin "UPDATE produto SET preco = $PRECO_FORA WHERE id = $ID" > /dev/null
req GET "/api/produtos/$ID/com-cache"; mostra GET "/api/produtos/$ID/com-cache"
confere "com-cache devolve o preço antigo (HIT desatualizado)" "$(preco "$CORPO")" "$PRECO_EM_CACHE"
req GET "/api/produtos/$ID/sem-cache"; mostra GET "/api/produtos/$ID/sem-cache"
confere "sem-cache devolve o preço do banco" "$(preco "$CORPO")" "$PRECO_FORA"
req POST /api/pedidos "{\"clienteId\":545,\"itens\":[{\"produtoId\":$ID,\"quantidade\":1}]}"
PEDIDO_ID=$(grep -oE '^\{"id":[0-9]+' <<< "$CORPO" | cut -d: -f2)
printf '  POST  /api/pedidos (produto %s)            -> HTTP %s | X-SQL-Count: %s | pedido %s\n' "$ID" "$STATUS" "$SQL" "$PEDIDO_ID"
confere "preço cobrado no pedido vem do banco, não do cache" \
    "$(sql_admin "SELECT preco_unitario FROM item_pedido WHERE pedido_id = $PEDIDO_ID")" "$PRECO_FORA"
sql_admin "DELETE FROM item_pedido WHERE pedido_id = $PEDIDO_ID; DELETE FROM pedido WHERE id = $PEDIDO_ID" > /dev/null
echo "  (pedido $PEDIDO_ID removido para manter a base reproduzível)"
echo "  O valor antigo continuaria sendo exibido por até $(redis TTL "$CHAVE") s (TTL restante)."
echo

echo "--- Restaurando o preço original ($PRECO_ORIGINAL)"
req PUT "/api/produtos/$ID" "$CORPO_ORIGINAL"
confere "HTTP do PUT" "$STATUS" 200
confere "EXISTS (invalidada de novo)" "$(redis EXISTS "$CHAVE")" 0
echo

echo "--- Passo 8: comparação sequencial em $N_COMPARACAO produtos distintos (ids 1..$N_COMPARACAO)"
for i in $(seq 1 50); do req GET "/api/produtos/1/sem-cache"; done   # aquecimento da JVM
redis FLUSHDB > /dev/null
rodada sem-cache "A sem cache:"
rodada com-cache "B com cache (MISS, frio):"
rodada com-cache "B com cache (HIT, quente):"
printf '  Actuator cache.gets (acumulado): hit=%s miss=%s\n' "$(metrica hit)" "$(metrica miss)"
echo

echo "--- Passo 9: escala do BigDecimal (produto 8, preço com zero final)"
redis DEL produtos::8 > /dev/null
req GET /api/produtos/8/com-cache; mostra GET /api/produtos/8/com-cache
confere "X-SQL-Count (MISS)" "$SQL" 1
printf '  Redis: GET produtos::8 = %s\n' "$(redis GET produtos::8)"
req GET /api/produtos/8/com-cache
confere "X-SQL-Count (HIT)" "$SQL" 0
confere "preço preserva a escala (788.60, não 788.6)" "$(preco "$CORPO")" "788.60"
compara_bytes 8
echo

echo "--- Passo 10: produto inexistente não vai para o cache"
redis FLUSHDB > /dev/null   # as chaves do passo 8 expiram sozinhas e mudariam o DBSIZE durante a medição
CHAVES_ANTES=$(redis DBSIZE)
req GET /api/produtos/999999/com-cache; mostra GET /api/produtos/999999/com-cache
confere "HTTP" "$STATUS" 404
confere "EXISTS produtos::999999" "$(redis EXISTS produtos::999999)" 0
confere "DBSIZE inalterado" "$(redis DBSIZE)" "$CHAVES_ANTES"
echo

echo "--- Passo 11: comandos que a aplicação envia ao Redis (redis-cli MONITOR durante um MISS e um HIT)"
redis DEL produtos::20 > /dev/null
# MONITOR roda por 3 s dentro do container; AUTH nunca aparece (o Redis o omite) e o PING do healthcheck é filtrado.
docker compose exec -T redis timeout 3 redis-cli MONITOR > "$TMP/monitor.txt" 2>/dev/null &
MONITOR_PID=$!
sleep 1
req GET /api/produtos/20/com-cache; echo "  GET /api/produtos/20/com-cache -> X-SQL-Count: $SQL (MISS)"
req GET /api/produtos/20/com-cache; echo "  GET /api/produtos/20/com-cache -> X-SQL-Count: $SQL (HIT)"
wait "$MONITOR_PID" || true
grep -v -iE '"(ping|auth|hello|monitor)"|^OK' "$TMP/monitor.txt" | sed -E 's/^[0-9.]+ \[[^]]*\] /  /'
confere "comandos GET enviados" "$(grep -c '"GET" "produtos::20"' "$TMP/monitor.txt")" 2
confere "comandos SET enviados (só no MISS)" "$(grep -c '"SET" "produtos::20"' "$TMP/monitor.txt")" 1
echo

echo "=== Verificações com falha: $FALHAS"
exit "$FALHAS"
