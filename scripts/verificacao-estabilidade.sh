#!/usr/bin/env bash
# Teste de fumaça antes do k6 (não é medição de desempenho): cerca de 50 requisições concorrentes a cada
# endpoint que o k6 vai usar. Confere 0 erros HTTP, nenhum timeout do pool Hikari no log e health UP no fim.
#
# Sobe a própria instância da API (porta 18080 ou PORTA_EXPERIMENTO) com SQL_LOG_LEVEL=info, para ler o log.
# Pré-requisitos: docker compose up -d, jq.
# Uso: scripts/verificacao-estabilidade.sh
# Saída: resultados/verificacao-estabilidade.txt
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

PORTA=${PORTA_EXPERIMENTO:-18080}
BASE=http://localhost:$PORTA
CONCORRENCIA=50
SAIDA=resultados/verificacao-estabilidade.txt
ENDPOINTS=(
    "/api/produtos/10/sem-cache"
    "/api/produtos/10/com-cache"
    "/api/clientes/1/pedidos?page=0&size=20"
    "/api/experimentos/pedidos/lazy?limite=10"
    "/api/experimentos/pedidos/eager?limite=10"
    "/api/experimentos/pedidos/join-fetch?limite=10"
    "/api/experimentos/pedidos/nativa?limite=10"
)
TMP=$(mktemp -d)
API_PID=""
ERROS=0

parar_api() {
    if [ -n "$API_PID" ]; then
        kill "$API_PID" 2>/dev/null || true
        wait "$API_PID" 2>/dev/null || true
        API_PID=""
    fi
}
trap 'parar_api; rm -rf "$TMP"' EXIT

if ss -ltn | grep -q ":$PORTA "; then
    echo "A porta $PORTA já está em uso; defina outra com PORTA_EXPERIMENTO=<porta>."
    exit 1
fi

echo "Empacotando a aplicação..."
./mvnw -q -DskipTests package
JAR=$(ls target/trabalho-a2-*.jar | grep -v plain | head -1)
SQL_LOG_LEVEL=info SERVER_PORT=$PORTA java -jar "$JAR" > "$TMP/api.log" 2>&1 &
API_PID=$!
for _ in $(seq 1 90); do curl -s -o /dev/null "$BASE/actuator/health" && break; sleep 1; done

exec > >(tee "$SAIDA") 2>&1
echo "=== Verificação de estabilidade — $(date '+%Y-%m-%d %H:%M:%S')"
echo "$CONCORRENCIA requisições disparadas ao mesmo tempo (xargs -P $CONCORRENCIA) por endpoint; pool Hikari de ${DB_POOL_SIZE:-10} conexões."
# Cache vazio no início, para que o lote do /com-cache exercite o MISS concorrente.
docker compose exec -T redis redis-cli DEL produtos::10 > /dev/null
echo

printf '%-48s %8s %8s %10s %12s\n' endpoint "HTTP 200" "erros" "soma SQL" "maior tempo"
for endpoint in "${ENDPOINTS[@]}"; do
    seq "$CONCORRENCIA" | xargs -P "$CONCORRENCIA" -I{} \
        curl -s -o /dev/null -w '%{http_code} %header{x-sql-count} %{time_total}\n' "$BASE$endpoint" > "$TMP/lote.txt"
    ok=$(awk '$1 == 200' "$TMP/lote.txt" | wc -l)
    erros=$((CONCORRENCIA - ok))
    ERROS=$((ERROS + erros))
    printf '%-48s %8s %8s %10s %10s s\n' "$endpoint" "$ok" "$erros" \
        "$(awk '{ s += $2 } END { print s }' "$TMP/lote.txt")" \
        "$(sort -k3 -n "$TMP/lote.txt" | tail -1 | awk '{ print $3 }')"
done
echo

TIMEOUTS_POOL=$(grep -cE 'Connection is not available|request timed out after' "$TMP/api.log" || true)
LINHAS_ERRO=$(grep -cE ' ERROR ' "$TMP/api.log" || true)
SAUDE=$(curl -s "$BASE/actuator/health" | jq -r '.status')
echo "Timeouts do pool Hikari no log: $TIMEOUTS_POOL"
echo "Linhas ERROR no log da API: $LINHAS_ERRO"
echo "Health no fim: $SAUDE"
echo "Chaves no Redis após o teste: $(docker compose exec -T redis redis-cli DBSIZE) (removidas em seguida)"
docker compose exec -T redis redis-cli DEL produtos::10 > /dev/null
echo
# Observação: com o cache vazio, as 50 requisições simultâneas ao /com-cache tendem a ser todas MISS
# (soma SQL = 50): nenhuma encontra a chave antes da primeira gravação. @Cacheable sem sync não coordena
# requisições concorrentes (cache stampede); relevante para o cenário de cache frio do k6.
FALHAS=$((ERROS + TIMEOUTS_POOL + LINHAS_ERRO))
[ "$SAUDE" = UP ] || FALHAS=$((FALHAS + 1))
echo "=== Resultado: $([ "$FALHAS" -eq 0 ] && echo 'estável (0 erros)' || echo "$FALHAS problema(s)")"
exit "$FALHAS"
