#!/usr/bin/env bash
# Experimento LAZY x EAGER x consultas otimizadas (enunciado, seção 4).
#
# O script sobe a própria instância da API na porta 18080 (PORTA_EXPERIMENTO), sem interferir numa
# API rodando na 8080:
#   1) SQL_LOG_LEVEL=info  -> medições e comparação dos JSONs (log de SQL distorceria o tempo)
#   2) SQL_LOG_LEVEL=debug -> evidência dos SQLs gerados, com limite=3
# Pré-requisitos: docker compose up -d, jq.
# Uso: scripts/experimento-persistencia.sh
#   LIMITES_EXPERIMENTO="100" DIR_SAIDA=/tmp/x scripts/experimento-persistencia.sh   (verificação parcial)
# Saída: resultados/persistencia/persistencia.csv, persistencia.txt e sql-<estrategia>.txt
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

PORTA=${PORTA_EXPERIMENTO:-18080}
BASE=http://localhost:$PORTA
API=$BASE/api/experimentos/pedidos
DIR=${DIR_SAIDA:-resultados/persistencia}
CSV=$DIR/persistencia.csv
TXT=$DIR/persistencia.txt
read -r -a LIMITES <<< "${LIMITES_EXPERIMENTO:-10 100 1000}"
ESTRATEGIAS=(lazy eager join-fetch nativa resumo-lazy resumo-eager)
PRINCIPAIS=(eager join-fetch nativa)   # comparadas com lazy: devem devolver JSON idêntico
AQUECIMENTO=3
MEDIDAS=5
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

# $1 = nível do log de SQL, $2 = arquivo de log; variáveis extras de ambiente vêm antes da chamada.
iniciar_api() {
    if ss -ltn | grep -q ":$PORTA "; then
        echo "A porta $PORTA já está em uso; defina outra com PORTA_EXPERIMENTO=<porta>."
        exit 1
    fi
    SQL_LOG_LEVEL=$1 SERVER_PORT=$PORTA java -jar "$JAR" > "$2" 2>&1 &
    API_PID=$!
    for _ in $(seq 1 90); do
        curl -s -o /dev/null "$BASE/actuator/health" && return 0
        sleep 1
    done
    echo "A API não subiu; log em $2"
    exit 1
}

# Uma requisição: preenche TEMPO_MS, SQL e BYTES e guarda o corpo em $TMP/corpo.json.
requisitar() {
    local status tempo
    read -r status tempo BYTES < <(curl -s -D "$TMP/h" -o "$TMP/corpo.json" \
        -w '%{http_code} %{time_total} %{size_download}\n' "$1")
    if [ "$status" != 200 ]; then
        echo "HTTP $status em $1"
        exit 1
    fi
    SQL=$(grep -i '^x-sql-count' "$TMP/h" | tr -d '\r' | awk '{print $2}')
    TEMPO_MS=$(awk -v t="$tempo" 'BEGIN { printf "%.2f", t * 1000 }')
}

# Quantidade de pedidos e de itens no corpo (lista ou objeto único).
contar() {
    jq -r 'if type == "array" then . else [.] end
           | [length, (map(.itens // [] | length) | add // 0)] | @tsv' "$TMP/corpo.json"
}

# $1 = estratégia, $2 = limite (rótulo), $3 = URL. Descarta o aquecimento e registra a mediana.
medir() {
    local pedidos itens mediana minimo maximo
    for _ in $(seq "$AQUECIMENTO"); do requisitar "$3"; done
    : > "$TMP/tempos"
    for _ in $(seq "$MEDIDAS"); do
        requisitar "$3"
        echo "$TEMPO_MS" >> "$TMP/tempos"
    done
    read -r pedidos itens < <(contar)
    mediana=$(sort -n "$TMP/tempos" | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }')
    minimo=$(sort -n "$TMP/tempos" | head -1)
    maximo=$(sort -n "$TMP/tempos" | tail -1)
    echo "$1,$2,$SQL,$mediana,$minimo,$maximo,$BYTES,$pedidos,$itens" >> "$CSV"
    printf '  %-13s %-6s SQLs %5s | mediana %9s ms | %8s bytes | %4s pedidos, %4s itens\n' \
        "$1" "$2" "$SQL" "$mediana" "$BYTES" "$pedidos" "$itens"
}

# Compara o JSON normalizado (jq -S) de duas rotas.
compara_json() {
    curl -s "$API/$1" | jq -S . > "$TMP/a.json"
    curl -s "$API/$2" | jq -S . > "$TMP/b.json"
    if cmp -s "$TMP/a.json" "$TMP/b.json"; then
        printf '  [OK]     %-28s = %-28s (%s bytes)\n' "$1" "$2" "$(wc -c < "$TMP/a.json")"
    else
        printf '  [FALHOU] %-28s difere de %s\n' "$1" "$2"
        FALHAS=$((FALHAS + 1))
    fi
}

# $1 = nome do arquivo, $2 = URL. Salva os SQLs (e os parâmetros) que a requisição gerou.
evidencia_sql() {
    local arquivo=$DIR/sql-$1.txt inicio
    inicio=$(wc -l < "$TMP/api-debug.log")
    requisitar "$2"
    sleep 0.5
    {
        echo "# GET ${2#"$BASE"}"
        echo "# X-SQL-Count: $SQL"
        tail -n +"$((inicio + 1))" "$TMP/api-debug.log" | awk '
            /org\.hibernate\.SQL/ { n++; printf "\n-- SQL %d\n", n; dentro = 1; next }
            /org\.hibernate\.orm\.jdbc\.bind/ { sub(/.*: /, ""); print "    -- " $0; next }
            /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/ { dentro = 0 }
            dentro && NF { print }'
    } > "$arquivo"
    printf '  %-26s X-SQL-Count %s -> %s\n' "${2#"$API"}" "$SQL" "$arquivo"
}

mkdir -p "$DIR"
# PULAR_EMPACOTAMENTO=1 reaproveita o jar existente (usado pelo experimento de índices, que já tem uma
# instância da API rodando a partir dele).
if [ -z "${PULAR_EMPACOTAMENTO:-}" ]; then
    echo "Empacotando a aplicação..."
    ./mvnw -q -DskipTests package
fi
JAR=$(ls target/trabalho-a2-*.jar | grep -v plain | head -1)

exec > >(tee "$TXT") 2>&1
echo "=== Experimento de persistência — $(date '+%Y-%m-%d %H:%M:%S')"
echo "Base: 100.000 pedidos (os 'limite' primeiros por id). $AQUECIMENTO aquecimentos descartados + $MEDIDAS medidas por linha."
echo "Tempo = mediana de curl time_total; SQLs = header X-SQL-Count; API com SQL_LOG_LEVEL=info."
echo

iniciar_api info "$TMP/api-info.log"

echo "--- Aquecimento geral da JVM (descartado)"
for _ in $(seq 5); do
    for e in "${ESTRATEGIAS[@]}"; do requisitar "$API/$e?limite=100"; done
    requisitar "$API/eager/1"
done
echo

echo "--- Medições"
echo "estrategia,limite,sqls,mediana_ms,min_ms,max_ms,bytes,pedidos,itens" > "$CSV"
for limite in "${LIMITES[@]}"; do
    for e in "${ESTRATEGIAS[@]}"; do medir "$e" "$limite" "$API/$e?limite=$limite"; done
done
medir eager-por-id "id=1" "$API/eager/1"
echo

echo "--- Mesmo resultado em todas as estratégias (JSON normalizado com jq -S)"
for limite in "${LIMITES[@]}"; do
    for e in "${PRINCIPAIS[@]}"; do compara_json "lazy?limite=$limite" "$e?limite=$limite"; done
    compara_json "resumo-lazy?limite=$limite" "resumo-eager?limite=$limite"
done
echo

parar_api
LOGGING_LEVEL_ORG_HIBERNATE_ORM_JDBC_BIND=trace iniciar_api debug "$TMP/api-debug.log"
echo "--- Evidências de SQL (limite=3, com parâmetros)"
for e in "${ESTRATEGIAS[@]}"; do evidencia_sql "$e" "$API/$e?limite=3"; done
evidencia_sql eager-por-id "$API/eager/1"
parar_api
echo

echo "=== Verificações com falha: $FALHAS"

exit "$FALHAS"
