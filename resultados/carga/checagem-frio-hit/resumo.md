# Resumo dos testes de carga (k6)

Gerado por `scripts/gerar_graficos.py` a partir de `resultados/carga/checagem-frio-hit/`. Cada valor é a **mediana das repetições** (3 por linha); entre parênteses, o mínimo e o máximo entre elas. Latências do `http_req_duration` do k6; throughput = requisições por segundo concluídas; CPU em % de um núcleo (100% = 1 núcleo inteiro; a máquina tem 12 lógicos). Os deltas do banco incluem a cauda do aquecimento do mesmo alvo (estatísticas publicadas com atraso), por isso são lidos como proporções (por transação, por requisição) e não em absoluto.

## Cenário 1 — cache

### Latência, throughput e erros

| Alvo | VUs | Média (ms) | p95 (ms) | p99 (ms) | Throughput (req/s) | Erros (%) |
|---|---|---:|---:|---:|---:|---:|
| Com cache, HIT | 100 | 6,57 (6,09–8,07) | 12,59 (11,38–15,77) | 17,74 (15,99–22,99) | 14.618 (11.898–15.769) | 0,00 (0,00–0,00) |
| Partida a frio | 100 | 6,97 (6,42–7,11) | 13,48 (12,04–13,53) | 18,83 (17,13–19,49) | 13.742 (13.492–14.970) | 0,00 (0,00–0,00) |

### Recursos (amostras a cada ~2 s durante a rodada)

| Alvo | VUs | CPU API média / pico | CPU PostgreSQL média / pico | CPU k6 média | Memória JVM máx (MB) | Hikari ativas máx | Hikari pendentes máx |
|---|---|---:|---:|---:|---:|---:|---:|
| Com cache, HIT | 100 | 431 / 459 | 1 / 6 | 382 | 363 | 0 | 0 |
| Partida a frio | 100 | 427 / 451 | 3 / 25 | 377 | 361 | 0 | 0 |

### Banco e cache

| Alvo | VUs | Taxa de HIT (%) | MISS na rodada | MISS redundantes (frio) | Transações do banco por requisição |
|---|---|---:|---:|---:|---:|
| Com cache, HIT | 100 | 100,0 | 0 | — | 0,000 |
| Partida a frio | 100 | 99,8 | 959 | 58 | 0,002 |

## Rodadas com falha do k6

Nenhuma.
