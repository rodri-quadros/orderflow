# Análise preliminar dos testes de carga (rascunho para a Etapa 10)

> Registro da Etapa 9, mantido como histórico. A versão final e revisada está no README, seções 3.8 e 6.

Base: [resumo.md](resumo.md) e [resumo.csv](resumo.csv), gerados por `scripts/gerar_graficos.py` a partir das 132
rodadas em `resultados/carga/` (3 cenários × alvos × 4 níveis × 3 repetições, 30 s medidos cada). Todos os
números abaixo são medianas das 3 repetições; as razões foram calculadas a partir do `resumo.csv`.
Ambiente: [ambiente.txt](ambiente.txt).

## Visão geral

| Cenário (100 VUs) | Pior alvo | Melhor alvo | Throughput | p95 |
|---|---|---|---:|---:|
| Cache | sem cache: 7.311 req/s, p95 32,6 ms | HIT: 17.373 req/s, p95 10,2 ms | 2,4× | 3,2× menor |
| Persistência | LAZY: 725 req/s, p95 221,7 ms | SQL nativo: 3.496 req/s, p95 57,4 ms | 4,8× | 3,9× menor |
| Índice | sem índice: 1.003 req/s, p95 177,1 ms | com índice: 6.816 req/s, p95 35,3 ms | 6,8× | 5,0× menor |

**Nenhuma rodada teve erro** (0,00% em todas as 132). A maior latência individual foi 1,38 s, abaixo do
`connection-timeout` de 5 s do Hikari, que é quem transformaria a espera em erro.

## Um fato que explica quase tudo: modelo fechado + saturação
Com `constant-vus` e sem think time, cada VU só envia a próxima requisição depois de receber a anterior. Quando um
recurso satura, o throughput fica constante e a latência cresce em proporção aos VUs. A Lei de Little
(latência média ≈ VUs / throughput) confere com o medido:

| Alvo | 10 VUs | 100 VUs | 200 VUs |
|---|---|---|---|
| LAZY | 14,7 ms previstos × 14,5 medidos | 137,9 × 137,2 | 265,6 × 264,3 |
| SQL nativo | 3,0 × 2,8 | 28,6 × 28,4 | 57,1 × 56,8 |
| Sem índice | 10,1 × 9,9 | 99,7 × 99,3 | 196,4 × 195,5 |
| Sem cache | 1,2 × 1,1 | 13,7 × 13,5 | 35,3 × 35,0 |

Ou seja, a partir de 10 VUs (persistência e índice) ou de 50 VUs (cache), aumentar os usuários só aumenta a fila.
Cada otimização eleva o patamar de throughput; o tempo de espera vem do quanto o patamar fica abaixo da demanda.

## Perguntas da seção 6.7

### 1. Qual técnica apresentou os maiores ganhos?
O **índice composto**: throughput de 6,7× a 7,0× maior em todos os níveis, p95 de 4,8× a 7,3× menor. Por
transação, o banco passou a ler 23 blocos e 20 tuplas, contra 903,6 blocos e cerca de 99.950 tuplas sem índice
(a tabela inteira). Depois vêm as **consultas otimizadas** (JOIN FETCH 4,0× a 4,2×; SQL nativo 4,7× a 5,0× sobre o
LAZY) e o **cache com HIT** (1,7× a 2,5×).

### 2. Os ganhos se mantiveram quando a carga aumentou?
- **Índice e persistência: sim, quase constantes.** Os dois lados de cada comparação já estão saturados com
  10 VUs, então a razão entre os patamares se mantém (índice 7,0× → 6,7×; nativo/LAZY 5,0× → 4,7×).
- **Cache: o ganho cresceu**, de 1,7× (10 VUs) para 2,3× (50) e 2,5× (200) em throughput, e de 1,9× para 3,4× no
  p95. Sem cache, as requisições disputam as 10 conexões do pool (até 187 pendentes com 200 VUs), e o throughput
  cai de 8.011 para 5.661 req/s. Com HIT, o pool não é usado (0 conexões ativas). O ganho só não cresce mais porque,
  com 200 VUs, o throughput do HIT também cai (17.373 → 13.953 req/s), limitado pela CPU da máquina (item 5).

### 3. Houve diferenças relevantes entre média, p95 e p99?
Sim. Com 200 VUs, o p95 ficou entre 1,6× e 2,7× a média, e o p99 entre 2,1× e 3,8×. As caudas mais longas estão
onde a espera pelo recurso é desigual: **sem cache, p99 = 3,8× a média** (133,5 × 35,0 ms), porque as requisições
esperam na fila do pool. LAZY e EAGER têm cauda proporcionalmente menor (p99 = 2,1× a 2,2× a média), porque todas
as requisições são igualmente lentas (41 SQLs cada). Em valor absoluto, porém, a cauda pior é a deles: p99 de 557 e
600 ms. Melhorar a média não basta: com 200 VUs, o índice reduziu a média em 6,7× (195 → 29 ms), mas o p99 em 4,1×
(430 → 106 ms).

### 4. Alguma otimização apresentou resultado inferior ao esperado?
- **Cache em MISS é mais lento que sem cache.** A média foi 1,86× maior com 10 VUs, 1,34× com 100 e 1,04× com 200.
  O MISS paga a consulta ao banco mais um GET e um SET no Redis. Com 200 VUs, o p95 do MISS (80,8 ms) ficou abaixo
  do sem cache (94,2 ms), com throughput parecido (5.446 × 5.661 req/s). Uma hipótese é que as idas ao Redis
  espaçam a chegada das requisições ao pool, reduzindo a fila (168 × 187 pendentes); não foi confirmada.
- **`@Cacheable(sync = true)` não reduziu o efeito manada.** MISS redundantes na partida a frio: 6, 37, 64 e 128
  (sem sync) contra 7, 38, 66 e 137 (com sync) para 10, 50, 100 e 200 VUs, diferenças dentro da variação entre
  repetições. Confirma, sob carga, a leitura do bytecode: o `RedisCache` do Spring Data Redis 4.1, com o writer sem
  trava, não sincroniza.
- **EAGER não trouxe ganho nenhum sobre LAZY** (725 × 717 req/s com 100 VUs). Em consulta de lista, os dois fazem
  as mesmas 41 consultas por requisição (Etapa 6).
- **O SQL nativo rendeu só 16% a 20% a mais que o JOIN FETCH** em throughput (p95 de 13% a 18% menor). O salto
  grande foi eliminar o N+1; o nativo acrescenta pouco a isso.
- **Partida a frio teve throughput um pouco maior que o HIT pré-carregado** (19.451 × 17.373 req/s com 100 VUs),
  embora as duas sejam praticamente 100% HIT depois do primeiro segundo. A diferença provavelmente vem da ordem das
  rodadas: o HIT roda logo depois do sem cache, que exige o máximo de CPU do PostgreSQL. Isso não foi isolado e
  fica registrado como limitação (CPU móvel, temperatura).

### 5. Quais foram os principais gargalos?
| Gargalo | Onde | Evidência |
|---|---|---|
| **Pool Hikari (10 conexões)** | sem cache, MISS, persistência, índice | 10 conexões ativas o tempo todo e pendentes ≈ VUs − 10 (38 a 40 com 50 VUs, 86 a 90 com 100, 187 a 189 com 200); throughput constante e latência obedecendo a Lei de Little |
| **CPU do PostgreSQL** | sem índice | PostgreSQL com 800% a 816% (8 núcleos) e API com só 84% a 91%: cada requisição varre a tabela (903 blocos por transação) |
| **CPU da máquina (API + k6)** | cache HIT, partida a frio | API com cerca de 480% e k6 com cerca de 420% (quase 9 dos 12 núcleos lógicos), banco ocioso; o throughput do HIT cai de 17.373 para 13.953 req/s entre 100 e 200 VUs |
| **CPU da API (montagem de entidades)** | JOIN FETCH | API com cerca de 460% contra 288% do nativo, com o PostgreSQL mais baixo (250% × 425%): o custo extra do JOIN FETCH está na JVM (entidades, contexto de persistência) |
| **k6 na mesma máquina** | todos | k6 de 33% (LAZY) a 423% (HIT) de CPU, roubando núcleos da API e do banco exatamente nos cenários mais rápidos |

### 6. Como a redução das consultas ao banco influenciou o desempenho?
De forma direta, e medida:
- **Persistência:** de 41 SQLs por requisição (LAZY e EAGER, `limite=20`) para 2 (JOIN FETCH) e 1 (nativo). O
  throughput subiu de cerca de 720 para cerca de 3.000 e 3.500 req/s com a mesma conexão do pool, porque cada
  requisição a segura por muito menos tempo.
- **Cache:** de cerca de 1,03 transação por requisição (sem cache) para 0,000 (HIT). A requisição deixa de depender
  do pool, e o gargalo passa para a CPU da máquina.
- **Índice:** o número de consultas não mudou (1 por requisição), mas o trabalho de cada uma caiu de cerca de 99.950
  para 20 tuplas lidas. Menos trabalho por consulta tem o mesmo efeito que menos consultas.

### 7. Quais os custos e riscos das otimizações adotadas?
- **Cache:** dado desatualizado por até 5 min (TTL) se alguém escrever fora da API; MISS mais caro que não ter
  cache; efeito manada na partida a frio (até 128 consultas redundantes em 30 s com 200 VUs) que o `sync` não
  resolve nesta versão; dependência de mais um serviço (Redis fora do ar = +0,5 a 1 s por requisição).
- **Índice:** +3,1 MB (43% da tabela) e +33% de WAL por inserção (Etapa 7); precisa ser mantido em toda escrita.
- **JOIN FETCH:** mais CPU na API por requisição; precisa dos dois passos para não paginar em memória.
- **SQL nativo:** mapeamento manual, sem validação pelo `ddl-auto`, preso ao dialeto PostgreSQL; ganho adicional
  pequeno (16% a 20%).
- **EAGER:** carrega dados desnecessários (Etapa 6) sem nenhum ganho em lista.

## Perguntas de cache (seção 3.5) com os dados sob carga
1. **Quando o cache trouxe mais benefício?** Com HIT e carga alta: throughput 2,4× a 2,5× maior com 100 a 200 VUs,
   p95 3,2× a 3,4× menor, e o banco fora do caminho (0 transações por requisição, CPU do PostgreSQL de cerca de 180%
   para cerca de 1%). Com 1 usuário (Etapa 5) o ganho era de 14% no tempo médio.
2. **Volatilidade e TTL:** com 5 min, a pré-carga cobriu as rodadas inteiras com 100% de HIT. Com TTL próximo de
   zero (MISS contínuo), o desempenho ficou pior que sem cache, o que mostra que um TTL curto demais para dados
   pouco voláteis é pior que não ter cache.
3. **Riscos de dado desatualizado:** sem mudança em relação à Etapa 5 (preço exibido, não cobrado). A carga
   mostrou um risco operacional a mais: na partida a frio, cada VU extra gera MISS redundantes (cerca de 0,6 por VU
   em 30 s), e o `sync` não protege.
4. **O cache sempre melhorou o desempenho?** Não. Com MISS, foi de 1,04× a 1,86× mais lento na média, porque a
   taxa de acerto é o que decide. Na partida a frio, o custo das falhas iniciais se dilui rapidamente: cerca de
   1.000 MISS em cerca de 580 mil requisições (99,8% de HIT na rodada).

## Consistência entre repetições
A variação (máximo − mínimo) / mediana do throughput ficou abaixo de 15% em 10 dos 11 alvos e chegou a **21% no sem
cache**, causada por uma repetição mais lenta com 50 VUs (6.253 contra 7.390 e 7.804 req/s). Persistência é o
cenário mais estável (EAGER e nativo com 3%). As conclusões não dependem dessa variação: as diferenças entre os
alvos (1,7× a 7×) são muito maiores que ela.

## Limitações a citar no relatório
- **k6, API, PostgreSQL e Redis na mesma máquina:** um notebook com CPU móvel de 15 W, sujeita a variação de
  frequência por temperatura. O k6 chegou a usar cerca de 4 núcleos.
- **Programas do usuário abertos** (IDE, navegador, SQL Server) durante as medições, registrados em `ambiente.txt`.
  Uma carga de base alta no início do bloco de persistência (load average de 22 em 5 min) veio do bloco de cache que
  acabara de terminar.
- **Rodadas curtas** (30 s) e cenários só de leitura, com o banco inteiro em memória (todos os acessos foram `hit`,
  nenhum `read`).
- **Deltas do `pg_stat_database`** incluem a cauda do aquecimento do mesmo alvo e são lidos como proporções.
