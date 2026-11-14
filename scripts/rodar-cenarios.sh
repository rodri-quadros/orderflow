#!/usr/bin/env bash
# Testes de carga com k6 (enunciado, seção 6): cenários cache, persistencia e indice.
#
# Uso: scripts/rodar-cenarios.sh [cache|persistencia|indice|todos|checagem]   (padrão: todos)
#   checagem: HIT e partida a frio intercalados, 3 vezes, só com 100 VUs (Etapa 10), em
#   resultados/carga/checagem-frio-hit/ (fora do resumo principal).
# Parâmetros por variável de ambiente:
#   NIVEIS="10 50 100 200"  DURACAO=30s  AQUECIMENTO=10s  REPETICOES=3  AQUECIMENTO_INICIAL=30s
#   PORTA_EXPERIMENTO=18080 (a 8081 está ocupada nesta máquina)  DIR_SAIDA=resultados/carga
# Pré-requisitos: docker compose up -d; k6, psql e jq no host.
#
# Sobe a própria API (jar, SQL_LOG_LEVEL=info) uma vez por bloco e a mantém aquecida entre os níveis.
# Em cada rodada: aquecimento curto descartado, rodada medida (JSON do k6) e, em paralelo, amostras de CPU e
# memória (API, k6, PostgreSQL, Redis), pool Hikari e cache a cada ~2 s; antes e depois, deltas de
# pg_stat_database, cache.gets, idx_scan e chaves no Redis.
# Saída: resultados/carga/<cenario>/<alvo>/vus<N>_rep<R>.json, _amostras.csv e _metricas.json.
# Só leitura (nenhum POST/PUT/PATCH). Termina sem índice composto, com o Redis vazio e a API parada.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

set -a; . ./.env; set +a
export PGHOST=127.0.0.1 PGPORT=$POSTGRES_PORT PGUSER=$POSTGRES_ADMIN_USER PGDATABASE=$POSTGRES_DB
export PGPASSWORD=$POSTGRES_ADMIN_PASSWORD   # só no ambiente do psql; nunca impressa

CENARIO=${1:-todos}
read -r -a NIVEIS <<< "${NIVEIS:-10 50 100 200}"
DURACAO=${DURACAO:-30s}
AQUECIMENTO=${AQUECIMENTO:-10s}
REPETICOES=${REPETICOES:-3}
AQUECIMENTO_INICIAL=${AQUECIMENTO_INICIAL:-30s}
PORTA=${PORTA_EXPERIMENTO:-18080}
BASE=http://localhost:$PORTA
DIR=${DIR_SAIDA:-resultados/carga}
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
redis() { docker compose exec -T redis redis-cli "$@"; }
segundos() { case $1 in *m) echo $(( ${1%m} * 60 )) ;; *s) echo "${1%s}" ;; *) echo "$1" ;; esac; }

# Valor de uma métrica do Actuator ($1 = nome e filtros, ex.: "cache.gets?tag=result:hit").
metrica() { curl -s "$BASE/actuator/metrics/$1" | jq -r '.measurements[0].value // 0' 2>/dev/null || echo 0; }

indices_pedido() { sql -c "SELECT string_agg(indexname, ',' ORDER BY indexname) FROM pg_indexes WHERE tablename = 'pedido'"; }

# Variáveis extras de ambiente para a API vêm como argumentos (ex.: CACHE_TTL_PRODUTOS=1ms).
iniciar_api() {
    if ss -ltn | grep -q ":$PORTA "; then
        echo "A porta $PORTA já está em uso; defina outra com PORTA_EXPERIMENTO=<porta>."
        exit 1
    fi
    env SQL_LOG_LEVEL=info SERVER_PORT="$PORTA" "$@" java -jar "$JAR" > "$TMP/api.log" 2>&1 &
    API_PID=$!
    for _ in $(seq 1 90); do
        curl -s -o /dev/null "$BASE/actuator/health" && return 0
        sleep 1
    done
    echo "A API não subiu."
    exit 1
}

# CPU de um processo em ticks (utime + stime de /proc/<pid>/stat; 100 ticks = 1 s de um núcleo).
ticks() { awk '{ print $14 + $15 }' "/proc/$1/stat" 2>/dev/null || echo 0; }

# "123.4MiB" -> MB
para_mb() {
    awk -v v="$1" 'BEGIN {
        n = v + 0; u = v; sub(/^[0-9.]+/, "", u)
        f = (u == "GiB") ? 1024 : (u == "MiB") ? 1 : (u == "KiB") ? 1 / 1024 : (u == "kB") ? 1 / 1000 : 1 / 1048576
        printf "%.1f", n * f }'
}

# Amostra a cada ~2 s (o docker stats leva ~2 s) enquanto o k6 roda. CPU em % de um núcleo para todos.
amostrar() {
    local csv=$1 k6_pid=$2 inicio t_ant api_ant k6_ant agora api k6 dt linha_pg linha_redis
    echo "seg,api_cpu,k6_cpu,postgres_cpu,redis_cpu,postgres_mem_mb,redis_mem_mb,jvm_mem_mb,hikari_ativas,hikari_pendentes,cache_hit,cache_miss" > "$csv"
    inicio=$(date +%s.%N); t_ant=$inicio; api_ant=$(ticks "$API_PID"); k6_ant=$(ticks "$k6_pid")
    while kill -0 "$k6_pid" 2>/dev/null; do
        docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}}' "$PG_CONTAINER" "$REDIS_CONTAINER" > "$TMP/stats" 2>/dev/null || true
        agora=$(date +%s.%N); api=$(ticks "$API_PID"); k6=$(ticks "$k6_pid")
        dt=$(awk -v a="$agora" -v b="$t_ant" 'BEGIN { print a - b }')
        linha_pg=$(sed -n 1p "$TMP/stats"); linha_redis=$(sed -n 2p "$TMP/stats")
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
            "$(awk -v a="$agora" -v b="$inicio" 'BEGIN { printf "%.1f", a - b }')" \
            "$(awk -v d="$((api - api_ant))" -v t="$dt" 'BEGIN { printf "%.1f", d / t }')" \
            "$(awk -v d="$((k6 - k6_ant))" -v t="$dt" 'BEGIN { if (d < 0) d = 0; printf "%.1f", d / t }')" \
            "$(awk '{ sub("%", "", $1); print $1 }' <<< "$linha_pg")" \
            "$(awk '{ sub("%", "", $1); print $1 }' <<< "$linha_redis")" \
            "$(para_mb "$(awk '{ print $2 }' <<< "$linha_pg")")" \
            "$(para_mb "$(awk '{ print $2 }' <<< "$linha_redis")")" \
            "$(awk -v b="$(metrica jvm.memory.used)" 'BEGIN { printf "%.1f", b / 1048576 }')" \
            "$(metrica hikaricp.connections.active)" "$(metrica hikaricp.connections.pending)" \
            "$(metrica 'cache.gets?tag=result:hit')" "$(metrica 'cache.gets?tag=result:miss')" >> "$csv"
        t_ant=$agora; api_ant=$api; k6_ant=$k6
    done
}

foto_banco() {
    sql -c "SELECT xact_commit + xact_rollback, tup_returned, tup_fetched, blks_hit, blks_read
            FROM pg_stat_database WHERE datname = current_database()"
}
idx_scan() { sql -c "SELECT coalesce(sum(idx_scan), 0) FROM pg_stat_user_indexes WHERE indexrelname = 'idx_pedido_cliente_data'"; }

# $1 = script k6, $2 = ALVO do k6, $3 = VUs, $4 = duração; demais argumentos vão para o k6 (-e ...).
k6_rodar() {
    local script=$1 alvo=$2 vus=$3 duracao=$4
    shift 4
    k6 run --quiet --no-color -e BASE_URL="$BASE" -e ALVO="$alvo" -e VUS="$vus" -e DURACAO="$duracao" "$@" "k6/$script"
}

# $1 cenário, $2 rótulo do alvo (pasta), $3 script k6, $4 ALVO do k6, $5 VUs, $6 repetição, $7 aquecer (sim|nao)
rodar() {
    local cenario=$1 rotulo=$2 script=$3 alvo=$4 vus=$5 rep=$6 aquecer=$7 base k6_pid status=0 amostrador
    local banco_antes banco_depois hit_antes miss_antes hit_depois miss_depois idx_antes idx_depois
    mkdir -p "$DIR/$cenario/$rotulo"
    base=$DIR/$cenario/$rotulo/vus${vus}_rep${rep}

    [ "$aquecer" = sim ] && k6_rodar "$script" "$alvo" "$vus" "$AQUECIMENTO" > /dev/null 2>&1

    banco_antes=$(foto_banco); idx_antes=$(idx_scan)
    hit_antes=$(metrica 'cache.gets?tag=result:hit'); miss_antes=$(metrica 'cache.gets?tag=result:miss')

    # k6 direto (não via função): assim $! é o PID do próprio k6, usado na amostragem de CPU.
    k6 run --quiet --no-color -e BASE_URL="$BASE" -e ALVO="$alvo" -e VUS="$vus" -e DURACAO="$DURACAO" \
        -e SAIDA="$base.json" -e ROTULO="$cenario/$rotulo rep$rep" "k6/$script" > "$TMP/k6.out" 2>&1 &
    k6_pid=$!
    amostrar "${base}_amostras.csv" "$k6_pid" &
    amostrador=$!
    wait "$k6_pid" || status=$?
    wait "$amostrador" || true

    # Backends ociosos do PostgreSQL publicam as estatísticas em até 10 s; sem esta espera, a cauda da
    # rodada vazaria para a próxima. Os deltas do banco são analisados por transação, não em absoluto.
    sleep 11
    banco_depois=$(foto_banco); idx_depois=$(idx_scan)
    hit_depois=$(metrica 'cache.gets?tag=result:hit'); miss_depois=$(metrica 'cache.gets?tag=result:miss')

    awk -F'|' -v antes="$banco_antes" -v depois="$banco_depois" \
        -v cenario="$cenario" -v alvo="$rotulo" -v vus="$vus" -v rep="$rep" -v status="$status" \
        -v hit="$(awk -v a="$hit_antes" -v b="$hit_depois" 'BEGIN { print b - a }')" \
        -v miss="$(awk -v a="$miss_antes" -v b="$miss_depois" 'BEGIN { print b - a }')" \
        -v idx="$((idx_depois - idx_antes))" -v chaves="$(redis DBSIZE)" -v indices="$(indices_pedido)" \
        'BEGIN {
            split(antes, a, "|"); split(depois, d, "|")
            printf "{\"cenario\": \"%s\", \"alvo\": \"%s\", \"vus\": %s, \"rep\": %s, \"k6_status\": %s,\n", cenario, alvo, vus, rep, status
            printf " \"banco\": {\"transacoes\": %d, \"tup_returned\": %d, \"tup_fetched\": %d, \"blks_hit\": %d, \"blks_read\": %d},\n", d[1]-a[1], d[2]-a[2], d[3]-a[3], d[4]-a[4], d[5]-a[5]
            printf " \"cache\": {\"hit\": %d, \"miss\": %d}, \"idx_scan\": %d, \"redis_chaves\": %d, \"indices_pedido\": \"%s\"}\n", hit, miss, idx, chaves, indices
        }' > "${base}_metricas.json"

    printf '  %s' "$(grep -E 'VUs=' "$TMP/k6.out" || echo "$cenario/$rotulo rep$rep: k6 sem resumo")"
    if [ "$status" -ne 0 ]; then
        echo "  [FALHOU] k6 terminou com código $status"; tail -5 "$TMP/k6.out"; FALHAS=$((FALHAS + 1))
    fi
    jq -r '"    banco: \(.banco.transacoes) transações | cache: \(.cache.hit) hit / \(.cache.miss) miss | idx_scan +\(.idx_scan) | chaves no Redis: \(.redis_chaves)"' \
        "${base}_metricas.json"
}

aquecer_inicial() {   # $1 script, demais = alvos
    local script=$1
    shift
    for alvo in "$@"; do k6_rodar "$script" "$alvo" 50 "$AQUECIMENTO_INICIAL" > /dev/null 2>&1; done
}

pre_carregar_cache() {
    jq -r '.[]' k6/dados/produtos-ativos.json \
        | xargs -P 10 -I{} curl -s -o /dev/null "$BASE/api/produtos/{}/com-cache"
}

confere_indices() {
    if [ "$(indices_pedido)" != "$1" ]; then
        echo "  [FALHOU] índices em pedido: $(indices_pedido) (esperado $1)"
        FALHAS=$((FALHAS + 1))
        exit 1
    fi
}

cenario_cache() {
    echo "=== Cenário 1 — cache ($(date '+%H:%M:%S'))"
    iniciar_api
    aquecer_inicial cache.js sem-cache com-cache
    for vus in "${NIVEIS[@]}"; do
        for rep in $(seq "$REPETICOES"); do
            rodar cache sem-cache cache.js sem-cache "$vus" "$rep" sim
            pre_carregar_cache   # HIT: todos os produtos ativos no Redis antes de cada repetição (TTL 5 min)
            rodar cache com-cache-hit cache.js com-cache "$vus" "$rep" sim
            redis FLUSHDB > /dev/null   # partida a frio: cache vazio no início da rodada, sem aquecimento
            rodar cache frio-com-cache cache.js com-cache "$vus" "$rep" nao
            redis FLUSHDB > /dev/null
            rodar cache frio-com-cache-sync cache.js com-cache-sync "$vus" "$rep" nao
        done
    done
    parar_api

    echo "--- MISS contínuo: API com CACHE_TTL_PRODUTOS=1ms (toda leitura vai ao banco e regrava o Redis)"
    redis FLUSHDB > /dev/null
    iniciar_api CACHE_TTL_PRODUTOS=1ms
    aquecer_inicial cache.js com-cache
    for vus in "${NIVEIS[@]}"; do
        for rep in $(seq "$REPETICOES"); do
            rodar cache com-cache-miss cache.js com-cache "$vus" "$rep" sim
        done
    done
    parar_api
    redis FLUSHDB > /dev/null
}

cenario_persistencia() {
    echo "=== Cenário 2 — persistência, limite=20 ($(date '+%H:%M:%S'))"
    iniciar_api
    aquecer_inicial persistencia.js lazy eager join-fetch nativa
    for vus in "${NIVEIS[@]}"; do
        for rep in $(seq "$REPETICOES"); do
            for alvo in lazy eager join-fetch nativa; do
                rodar persistencia "$alvo" persistencia.js "$alvo" "$vus" "$rep" sim
            done
        done
    done
    parar_api
}

cenario_indice() {
    echo "=== Cenário 3 — índices ($(date '+%H:%M:%S'))"
    sql -q -f db/indice/remover_indice.sql 2> /dev/null
    iniciar_api
    aquecer_inicial indice.js ""
    for vus in "${NIVEIS[@]}"; do
        for rep in $(seq "$REPETICOES"); do
            # Alterna o estado a cada repetição, para que a deriva da JVM afete os dois igualmente.
            sql -q -f db/indice/remover_indice.sql 2> /dev/null
            confere_indices pedido_pkey
            rodar indice sem-indice indice.js "" "$vus" "$rep" sim
            sql -q -f db/indice/criar_indice.sql
            confere_indices idx_pedido_cliente_data,pedido_pkey
            rodar indice com-indice indice.js "" "$vus" "$rep" sim
        done
    done
    parar_api
    sql -q -f db/indice/remover_indice.sql 2> /dev/null
}

# Etapa 10: a partida a frio teve throughput maior que o HIT pré-carregado. Aqui as duas condições se
# alternam (HIT, frio, HIT, frio, HIT, frio) com o mesmo aquecimento: o do frio enche o cache, que é
# esvaziado logo antes da rodada medida.
cenario_checagem() {
    echo "=== Checagem HIT × partida a frio, 100 VUs ($(date '+%H:%M:%S'))"
    iniciar_api
    aquecer_inicial cache.js sem-cache com-cache
    for rep in $(seq "$REPETICOES"); do
        pre_carregar_cache
        rodar cache com-cache-hit cache.js com-cache 100 "$rep" sim
        k6_rodar cache.js com-cache 100 "$AQUECIMENTO" > /dev/null 2>&1
        redis FLUSHDB > /dev/null
        rodar cache frio-com-cache cache.js com-cache 100 "$rep" nao
    done
    parar_api
    redis FLUSHDB > /dev/null
}

registrar_ambiente() {
    {
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') — cenário: $CENARIO | níveis: ${NIVEIS[*]} | duração $DURACAO | aquecimento $AQUECIMENTO | repetições $REPETICOES"
        echo "SO: $(lsb_release -ds 2>/dev/null) | kernel $(uname -r)"
        echo "CPU: $(lscpu | sed -n 's/^\(Model name\|Nome do modelo\): *//p' | head -1) | $(nproc) CPUs lógicas"
        echo "RAM: $(free -h | awk '/^(Mem|Mem\.):/ { print $2 " total, " $7 " disponível" }')"
        echo "Carga média (1/5/15 min): $(cut -d' ' -f1-3 /proc/loadavg)"
        echo "Java: $(java -version 2>&1 | head -1) | Spring Boot $(sed -n 's:.*<version>\(4[^<]*\)</version>.*:\1:p' pom.xml | head -1)"
        echo "PostgreSQL: $(sql -c 'SHOW server_version') | Redis: $(redis INFO server | sed -n 's/^redis_version://p' | tr -d '\r') | k6: $(k6 version | head -1)"
        echo "Pool Hikari: ${DB_POOL_SIZE:-10} conexões | connection-timeout 5 s | statement_timeout 10 s"
        echo "Base: $(sql -c "SELECT (SELECT count(*) FROM pedido) || ' pedidos, ' || (SELECT count(*) FROM item_pedido) || ' itens, ' || (SELECT count(*) FROM cliente) || ' clientes, ' || (SELECT count(*) FROM produto) || ' produtos'")"
        echo "k6, API, PostgreSQL e Redis na mesma máquina. Processos com mais CPU e memória no início do bloco:"
        ps -eo pcpu,pmem,rss,comm --sort=-pcpu | head -8 | sed 's/^/  /'
        echo
    } >> "$DIR/ambiente.txt"
}

estimar() {
    local por_rodada total=0 n=${#NIVEIS[@]} r=$REPETICOES a d i
    a=$(segundos "$AQUECIMENTO"); d=$(segundos "$DURACAO"); i=$(segundos "$AQUECIMENTO_INICIAL")
    por_rodada=$((a + d + 15))   # + espera das estatísticas e coleta
    case $1 in
        cache) total=$(( n * r * (2 * por_rodada + 2 * (d + 15) + 6) + n * r * por_rodada + 3 * i + 30 )) ;;
        persistencia) total=$(( n * r * 4 * por_rodada + 4 * i + 15 )) ;;
        indice) total=$(( n * r * 2 * por_rodada + i + 15 )) ;;
        checagem) total=$(( r * (2 * por_rodada + a) + 2 * i + 30 )) ;;
    esac
    echo "$total"
}

estado_final() {
    sql -q -f db/indice/remover_indice.sql 2> /dev/null
    redis FLUSHDB > /dev/null
    echo "--- Estado final: índices em pedido = $(indices_pedido) | chaves no Redis = $(redis DBSIZE) | API parada"
    echo "    checksum: $(sql -c "SELECT count(*) || ' | ' || sum(valor_total) FROM pedido")"
}

case $CENARIO in
    cache|persistencia|indice) CENARIOS=("$CENARIO") ;;
    checagem) CENARIOS=(checagem); NIVEIS=(100); DIR=${DIR_SAIDA:-resultados/carga/checagem-frio-hit} ;;
    todos) CENARIOS=(cache persistencia indice) ;;
    *) echo "Uso: $0 [cache|persistencia|indice|todos|checagem]"; exit 1 ;;
esac

command -v k6 > /dev/null || { echo "k6 não encontrado no PATH."; exit 1; }
mkdir -p "$DIR"
PG_CONTAINER=$(docker compose ps -q postgres)
REDIS_CONTAINER=$(docker compose ps -q redis)

TOTAL=0
for c in "${CENARIOS[@]}"; do TOTAL=$((TOTAL + $(estimar "$c"))); done
echo "Estimativa: $((TOTAL / 60)) min para ${CENARIOS[*]} (níveis ${NIVEIS[*]}, $REPETICOES repetições, $AQUECIMENTO + $DURACAO por rodada)."

echo "Empacotando a aplicação..."
./mvnw -q -DskipTests package
JAR=$(ls target/trabalho-a2-*.jar | grep -v plain | head -1)
registrar_ambiente

INICIO=$(date +%s)
for c in "${CENARIOS[@]}"; do "cenario_$c"; done
estado_final
echo "=== Concluído em $(( ($(date +%s) - INICIO) / 60 )) min | falhas: $FALHAS"
exit "$FALHAS"
