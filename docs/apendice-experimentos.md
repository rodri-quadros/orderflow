# Apêndice — detalhes dos experimentos

Complementa o [README](../README.md) com as tabelas completas e o passo a passo dos scripts. Tudo o que o
enunciado exige no relatório está no README. Este apêndice traz os detalhes que sustentam as conclusões.
Todos os números foram copiados dos arquivos de [resultados/](../resultados/), gerados pelos scripts.

- [A. Cache: experimento passo a passo](#a-cache-experimento-passo-a-passo)
- [B. LAZY, EAGER e consultas otimizadas: tabela completa](#b-lazy-eager-e-consultas-otimizadas-tabela-completa)
- [C. Índices: todos os planos](#c-índices-todos-os-planos)
- [D. Testes de carga: verificações de consistência](#d-testes-de-carga-verificações-de-consistência)
- [E. Testes funcionais por classe](#e-testes-funcionais-por-classe)

## A. Cache: experimento passo a passo

Fonte: [resultados/cache/experimento-cache.txt](../resultados/cache/experimento-cache.txt), gerado por
[scripts/experimento-cache.sh](../scripts/experimento-cache.sh) com a API em `CACHE_TTL_PRODUTOS=10s`
(TTL curto só para o passo 6). Produto 10, preço original 1419,87.

| Passo | Requisição | X-SQL-Count | Estado no Redis | Resultado |
|---|---|---:|---|---|
| 0 | `FLUSHDB` | — | vazio | estado inicial conhecido |
| 1 | GET `/sem-cache` (2×) | 1 e 1 | chave não existe | sem cache, sempre consulta o banco |
| 2 | GET `/com-cache` | 1 | chave criada, TTL 10 s | MISS |
| 3 | GET `/com-cache` | 0 | chave existe | HIT, mesmo corpo do passo 2 |
| 4 | PUT preço 1419,87 → 1519,87 | 2 | chave removida | invalidação |
| 5 | GET `/com-cache` (2×) | 1 e 0 | chave recriada | MISS com o preço novo, depois HIT |
| 6 | aguardar o TTL, depois GET `/com-cache` | 1 | expirou sozinha | MISS por expiração |
| 7 | UPDATE direto no banco, depois GET `/com-cache` | 0 | chave antiga | HIT com preço desatualizado |
| 7 | POST `/api/pedidos` com o mesmo produto | 4 | — | o preço cobrado é o do banco |
| 8 | 200 produtos distintos, sem cache, MISS e HIT | 200 / 200 / 0 | — | comparação sequencial (README, seção 3.6) |
| 9 | GET `/com-cache` do produto 8 (preço 788,60) | 1 e 0 | `"preco":788.60` | escala do `BigDecimal` preservada |
| 10 | GET `/com-cache` de produto inexistente | 1 | nenhuma chave criada | 404, nada vai para o cache |
| 11 | `redis-cli MONITOR` durante um MISS e um HIT | 1 e 0 | — | comandos `GET`, `SET ... PX`, `GET` |

Nos passos 3 e 9, o corpo do HIT é comparado byte a byte (`cmp`) com o de `/sem-cache` e é idêntico. O script
restaura o preço original e remove o pedido que criou, então a base continua idêntica à gerada.

Comandos que a aplicação envia ao Redis (passo 11; o `AUTH` não aparece no `MONITOR`):

```
"GET" "produtos::20"                                                         <- MISS: chave não existe
"SET" "produtos::20" "{\"id\":20,...,\"preco\":1236.44,...}" "PX" "10000"   <- grava com TTL
"GET" "produtos::20"                                                         <- HIT: devolve o JSON, sem SQL
```

### Por que `sync = true` não sincroniza nesta versão

O Spring trata `@Cacheable(sync = true)` como uma dica e delega a sincronização ao provedor. No Spring Data
Redis 4.1, `RedisCache.get(key, Callable)` chama o `RedisCacheWriter` passando a função que carrega o valor. O
writer padrão (sem trava) não usa `synchronized` nem lock nesse caminho: o método tem só o modificador
`ACC_PUBLIC` no bytecode (conferido com `javap` no jar). Só um writer criado com `enableLocking()` serializa os
acessos, e essa trava é distribuída (chave `produtos~lock` no Redis) e vale para o cache inteiro, não por chave.
A medição sob carga confirma: os MISS redundantes na partida a frio foram os mesmos com e sem `sync`
(README, seção 3.7).

## B. LAZY, EAGER e consultas otimizadas: tabela completa

Fonte: [resultados/persistencia/persistencia.txt](../resultados/persistencia/persistencia.txt) e
`persistencia.csv`, gerados por [scripts/experimento-persistencia.sh](../scripts/experimento-persistencia.sh).
Mediana de 5 requisições após 3 de aquecimento; SQLs pelo header `X-SQL-Count`; API com log de SQL desligado.

| Estratégia | Limite | SQLs | Mediana | Bytes | Pedidos / itens |
|---|---:|---:|---:|---:|---:|
| LAZY | 10 | 21 | 12,33 ms | 2.713 | 10 / 26 |
| EAGER (lista) | 10 | 21 | 10,91 ms | 2.713 | 10 / 26 |
| JOIN FETCH | 10 | 2 | 9,64 ms | 2.713 | 10 / 26 |
| Nativa | 10 | 1 | 6,43 ms | 2.713 | 10 / 26 |
| Grid LAZY | 10 | 11 | 8,07 ms | 943 | 10 / — |
| Grid EAGER | 10 | 21 | 11,57 ms | 943 | 10 / — |
| LAZY | 100 | 201 | 48,10 ms | 29.391 | 100 / 299 |
| EAGER (lista) | 100 | 201 | 45,12 ms | 29.391 | 100 / 299 |
| JOIN FETCH | 100 | 2 | 14,69 ms | 29.391 | 100 / 299 |
| Nativa | 100 | 1 | 7,84 ms | 29.391 | 100 / 299 |
| Grid LAZY | 100 | 101 | 18,54 ms | 9.512 | 100 / — |
| Grid EAGER | 100 | 201 | 35,44 ms | 9.512 | 100 / — |
| LAZY | 1000 | 1.937 | 237,18 ms | 295.258 | 1000 / 2995 |
| EAGER (lista) | 1000 | 1.937 | 233,30 ms | 295.258 | 1000 / 2995 |
| JOIN FETCH | 1000 | 2 | 44,89 ms | 295.258 | 1000 / 2995 |
| Nativa | 1000 | 1 | 13,13 ms | 295.258 | 1000 / 2995 |
| Grid LAZY | 1000 | 937 | 90,42 ms | 96.176 | 1000 / — |
| Grid EAGER | 1000 | 1.937 | 233,06 ms | 96.176 | 1000 / — |
| EAGER por id | id=1 | 1 | 4,59 ms | 406 | 1 / 5 |

O script também confere que o JSON (normalizado com `jq -S`) é idêntico entre LAZY, EAGER, JOIN FETCH e nativa
em todos os limites, e entre os dois grids. As consultas geradas com `limite=3`, com os parâmetros, estão em
`resultados/persistencia/sql-*.txt`.

### Alternativas não implementadas

- **Batch fetching** (`@BatchSize` ou `hibernate.default_batch_fetch_size`): mantém o código LAZY e carrega as
  associações pendentes em blocos (`WHERE pedido_id IN (...)`). Com 1000 pedidos e blocos de 100 seriam cerca de
  21 consultas. Ficou desligado de propósito, porque esconderia o N+1 que o experimento precisa mostrar.
- **Buscar em lote e montar em memória** (o "acesso repetitivo" da aula): 3 consultas fixas (pedidos, clientes
  `WHERE id IN`, itens `WHERE pedido_id IN`) e `Map` em Java. A API usa esse padrão na criação de pedido
  (`findAllById` + `Map<Long, Produto>`).

## C. Índices: todos os planos

Fonte: [resultados/indice/indice.csv](../resultados/indice/indice.csv), `indice.txt` e os planos completos em
[resultados/explain/](../resultados/explain/), gerados por [scripts/experimento-indice.sh](../scripts/experimento-indice.sh).

Consultas (em [db/indice/explain_pedidos_cliente.sql](../db/indice/explain_pedidos_cliente.sql)):
**A** é o SQL que a API gera (páginas 0 e 2, `LIMIT 20`), **B** é a do enunciado (sem limite) e **C** é a do
slide (com intervalo `data_pedido >= '2026-01-01'`). Banco: mediana de 10 `EXPLAIN ANALYZE`. API: mediana e p95
de 20 requisições. "Linhas" = linhas devolvidas pelo nó de varredura; "Removidas" = `Rows Removed by Filter`.

| Estado | Consulta | Cliente | Varredura (índice) | Sort | Linhas | Removidas | Buffers hit/read | Banco | API mediana / p95 |
|---|---|---:|---|---|---:|---:|---|---:|---|
| sem | A_pagina0 | 1 | Seq Scan | top-N heapsort | 225 | 99775 | 907/0 | 4,825 ms | 9,110 / 10,76 ms |
| sem | A_pagina2 | 1 | Seq Scan | top-N heapsort | 225 | 99775 | 907/0 | 4,189 ms | 9,740 / 11,10 ms |
| sem | B_sem_limite | 1 | Seq Scan | quicksort | 225 | 99775 | 907/0 | 2,689 ms | — |
| sem | C_intervalo | 1 | Seq Scan | quicksort | 100 | 99900 | 907/0 | 3,616 ms | — |
| sem | A_pagina0 | 545 | Seq Scan | quicksort | 9 | 99991 | 907/0 | 5,107 ms | 9,590 / 10,39 ms |
| sem | A_pagina2 | 545 | Seq Scan | quicksort | 9 | 99991 | 907/0 | 3,547 ms | 9,970 / 10,41 ms |
| sem | B_sem_limite | 545 | Seq Scan | quicksort | 9 | 99991 | 907/0 | 4,040 ms | — |
| sem | C_intervalo | 545 | Seq Scan | quicksort | 3 | 99997 | 907/0 | 3,162 ms | — |
| simples | A_pagina0 | 1 | Bitmap Heap Scan (idx_pedido_cliente) | top-N heapsort | 225 | 0 | 209/0 | 0,204 ms | 4,655 / 5,07 ms |
| simples | A_pagina2 | 1 | Bitmap Heap Scan (idx_pedido_cliente) | top-N heapsort | 225 | 0 | 209/0 | 0,217 ms | 4,840 / 5,20 ms |
| simples | B_sem_limite | 1 | Bitmap Heap Scan (idx_pedido_cliente) | quicksort | 225 | 0 | 209/0 | 0,241 ms | — |
| simples | C_intervalo | 1 | Bitmap Heap Scan (idx_pedido_cliente) | quicksort | 100 | 125 | 209/0 | 0,199 ms | — |
| simples | A_pagina0 | 545 | Bitmap Heap Scan (idx_pedido_cliente) | quicksort | 9 | 0 | 17/0 | 0,079 ms | 4,470 / 4,97 ms |
| simples | A_pagina2 | 545 | Bitmap Heap Scan (idx_pedido_cliente) | quicksort | 9 | 0 | 17/0 | 0,075 ms | 5,325 / 5,77 ms |
| simples | B_sem_limite | 545 | Bitmap Heap Scan (idx_pedido_cliente) | quicksort | 9 | 0 | 17/0 | 0,089 ms | — |
| simples | C_intervalo | 545 | Bitmap Heap Scan (idx_pedido_cliente) | quicksort | 3 | 6 | 17/0 | 0,081 ms | — |
| composto | A_pagina0 | 1 | Index Scan (idx_pedido_cliente_data) | — | 20 | 0 | 26/0 | 0,054 ms | 4,165 / 4,83 ms |
| composto | A_pagina2 | 1 | Index Scan (idx_pedido_cliente_data) | — | 60 | 0 | 66/0 | 0,081 ms | 4,880 / 7,72 ms |
| composto | B_sem_limite | 1 | Bitmap Heap Scan (idx_pedido_cliente_data) | quicksort | 225 | 0 | 210/0 | 0,246 ms | — |
| composto | C_intervalo | 1 | Bitmap Heap Scan (idx_pedido_cliente_data) | quicksort | 100 | 0 | 105/0 | 0,153 ms | — |
| composto | A_pagina0 | 545 | Bitmap Heap Scan (idx_pedido_cliente_data) | quicksort | 9 | 0 | 18/0 | 0,083 ms | 4,380 / 4,98 ms |
| composto | A_pagina2 | 545 | Bitmap Heap Scan (idx_pedido_cliente_data) | quicksort | 9 | 0 | 18/0 | 0,086 ms | 5,175 / 6,14 ms |
| composto | B_sem_limite | 545 | Bitmap Heap Scan (idx_pedido_cliente_data) | quicksort | 9 | 0 | 18/0 | 0,076 ms | — |
| composto | C_intervalo | 545 | Bitmap Heap Scan (idx_pedido_cliente_data) | quicksort | 3 | 0 | 12/0 | 0,073 ms | — |
| sem_final | A_pagina0 | 1 | Seq Scan | top-N heapsort | 225 | 99775 | 907/0 | 3,523 ms | 7,750 / 8,79 ms |
| sem_final | A_pagina2 | 1 | Seq Scan | top-N heapsort | 225 | 99775 | 907/0 | 3,181 ms | 7,940 / 9,60 ms |
| sem_final | B_sem_limite | 1 | Seq Scan | quicksort | 225 | 99775 | 907/0 | 3,114 ms | — |
| sem_final | C_intervalo | 1 | Seq Scan | quicksort | 100 | 99900 | 907/0 | 3,431 ms | — |
| sem_final | A_pagina0 | 545 | Seq Scan | quicksort | 9 | 99991 | 907/0 | 3,986 ms | 8,360 / 8,75 ms |
| sem_final | A_pagina2 | 545 | Seq Scan | quicksort | 9 | 99991 | 907/0 | 2,217 ms | 8,030 / 9,15 ms |
| sem_final | B_sem_limite | 545 | Seq Scan | quicksort | 9 | 99991 | 907/0 | 3,071 ms | — |
| sem_final | C_intervalo | 545 | Seq Scan | quicksort | 3 | 99997 | 907/0 | 4,162 ms | — |

O estado `sem_final` repete o "sem" na mesma JVM, já aquecida. É o controle que separa o efeito do índice do
aquecimento da JVM no tempo da API. O `X-SQL-Count` foi 1 em todas as páginas com resultado e 2 só na página 2
do cliente 545 (página vazia: a API confere se o cliente existe para decidir entre lista vazia e 404).

### Quando o composto não vira Index Scan

- **Consulta B (sem limite), cliente 1.** O Index Scan completo custaria 707,79 no plano; Bitmap + Sort custou
  484,66. Os 225 pedidos estão espalhados por 201 das 904 páginas (`Heap Blocks: exact=201`). Percorrer o índice
  em ordem saltaria entre páginas, enquanto o bitmap lê cada página uma vez, na ordem física, e ordenar 225
  linhas em memória é barato (quicksort, 38 kB). Com `LIMIT 20` a conta se inverte: o Index Scan paga só 20/193
  do custo (73,72).
- **Cliente 545, qualquer consulta.** Com 9 linhas o `LIMIT 20` não corta nada e ordenar 9 linhas é trivial.
  Bitmap + quicksort custa 41,6 e lê 18 páginas.
- **Consulta C (intervalo), cliente 1.** Usa Bitmap + Sort, mas o intervalo entra no `Index Cond`
  (`cliente_id = 1 AND data_pedido >= '2026-01-01'`): visita 96 páginas da tabela (`Heap Blocks: exact=96`) e
  não remove linha nenhuma por filtro. Com o índice simples, a data é conferida no heap: 201 páginas e
  `Rows Removed by Filter: 125`.

As estimativas do planejador ficaram próximas do real (193 estimadas × 225 reais no cliente 1; 10 × 9 no 545).
As consultas da Etapa 6 mantiveram os mesmos planos e o mesmo número de SQLs com o índice composto criado; o
script confere isso automaticamente.

### Custo de escrita

Inserção de 10.000 pedidos dentro de `BEGIN ... ROLLBACK`, seguida de `VACUUM`; mediana de 5 execuções.

| | Sem índice extra | + índice simples | + índice composto |
|---|---:|---:|---:|
| Tamanho do índice | — | 920 kB | 3.104 kB |
| Tempo da inserção | 105,332 ms | 114,583 ms | 112,936 ms |
| WAL gerado | 2.136 KB | 2.815 KB | 2.842 KB |

O tempo variou de 100 a 141 ms entre execuções, da mesma ordem da diferença entre os estados. O WAL é
determinístico e mostra o custo real: cada linha inserida grava também uma entrada em cada índice. O composto é
3,4× maior que o simples porque o PostgreSQL deduplica chaves repetidas em B-tree (cada `cliente_id` aparece em
média 10 vezes), e `(cliente_id, data_pedido)` é praticamente única.

## D. Testes de carga: verificações de consistência

Tabelas completas (mediana, mínimo e máximo das 3 repetições, para os 4 níveis): [resultados/carga/resumo.md](../resultados/carga/resumo.md).

### Lei de Little

Em modelo fechado e saturado, latência média ≈ VUs / throughput. Valores previstos (calculados do
`resumo.csv`) × medidos:

| Alvo | 10 VUs | 100 VUs | 200 VUs |
|---|---|---|---|
| LAZY | 14,7 × 14,5 ms | 137,9 × 137,2 ms | 265,6 × 264,3 ms |
| SQL nativo | 3,0 × 2,8 ms | 28,6 × 28,4 ms | 57,1 × 56,8 ms |
| Sem índice | 10,1 × 9,9 ms | 99,7 × 99,3 ms | 196,4 × 195,5 ms |
| Sem cache | 1,2 × 1,1 ms | 13,7 × 13,5 ms | 35,3 × 35,0 ms |

A diferença, de no máximo 1,4 ms, é provavelmente o tempo de cada iteração do k6 fora da requisição HTTP
(o `http_req_duration` mede só a requisição).

### Variação entre repetições

(máximo − mínimo) / mediana do throughput: até 15% em 10 dos 11 alvos; 21% no sem cache com 50 VUs (uma
repetição com 6.253 req/s, contra 7.390 e 7.804). EAGER e SQL nativo ficaram em até 3%.

### Checagem da partida a frio × HIT

`scripts/rodar-cenarios.sh checagem`: 100 VUs, HIT e partida a frio intercalados 3 vezes; no frio, o
aquecimento de 10 s enche o cache, e o `FLUSHDB` acontece logo antes da rodada medida. Fonte:
[resultados/carga/checagem-frio-hit/resumo.md](../resultados/carga/checagem-frio-hit/resumo.md).

| Rodada | HIT (req/s) | Partida a frio (req/s) |
|---|---:|---:|
| 1 | 11.898 | 14.970 |
| 2 | 15.769 | 13.492 |
| 3 | 14.618 | 13.742 |
| Mediana | 14.618 | 13.742 |

Na bateria principal, o frio teve mediana de 19.451 contra 17.373 req/s do HIT. Intercalados, o HIT ficou à
frente na mediana, e as faixas se sobrepõem: a diferença original era efeito de ordem e de estado térmico. A
primeira rodada (HIT, 11.898 req/s) é também a mais lenta da checagem, logo depois do aquecimento inicial.

## E. Testes funcionais por classe

`./mvnw clean verify`: 87 testes (1 pulado). Camada 1 sem Spring nem banco (25 testes); camada 2 com
`@SpringBootTest` e MockMvc contra o PostgreSQL e o Redis do Compose (62 testes).

| Classe | Cobre |
|---|---|
| `StatusPedidoTest` | as 9 combinações de `podeMudarPara` |
| `PedidoTest` | `adicionarItem` (referência inversa, `valorTotal` com 2 casas) e `alterarStatus` |
| `PedidoServiceTest` | repositórios mockados: cliente ou produto inexistente, inativo ou repetido, preço copiado, **uma única chamada a `findAllById`** |
| `ClienteServiceTest` | email duplicado, inclusive a violação de UNIQUE convertida em 409 |
| `ClienteControllerTest` | criação, busca, pedidos ordenados (1 SQL), página vazia (2 SQLs), paginação fora dos limites |
| `ProdutoControllerTest` | criação, busca sem cache (1 SQL), atualização, preço inválido, 404 |
| `PedidoControllerTest` | criação com preço do produto, busca com cliente e itens (1 SQL), transições de status, 400/404/409/422, preço histórico preservado |
| `ErrosApiTest` | 15 erros diferentes em `ProblemDetail`, sem SQL, nomes de tabela, classes ou stack trace |
| `ExperimentoControllerTest` | `X-SQL-Count` por estratégia com `limite=10` (21, 21, 2, 1, grids 11 e 21, por id 1) e JSON idêntico |
| `CacheIntegracaoTest` | MISS (1 SQL) → HIT (0) → PUT remove a chave → MISS com preço novo; HIT igual byte a byte; 404 sem chave; `com-cache-sync` usa a mesma chave |
| `StatementTimeoutTest` | `statement_timeout` = 10 s na conexão da aplicação; o `pg_sleep(11)` só com `-Dtestes.lentos=true` |
| `PedidosApplicationTests` | o contexto sobe (`ddl-auto: validate` aprova o mapeamento) |

Os testes que escrevem usam `@Transactional` e são desfeitos no fim. Os de cache precisam de commit (o evict só
acontece depois dele), então restauram o produto e a chave em `@AfterEach`. Os ids vêm de
[DadosTeste.java](../src/test/java/br/uva/pedidos/DadosTeste.java). Numa checagem de sanidade, remover o
`@CacheEvict` e buscar produto por produto na criação do pedido fez `CacheIntegracaoTest` e `PedidoServiceTest`
falharem, como esperado.

A verificação de estabilidade ([scripts/verificacao-estabilidade.sh](../scripts/verificacao-estabilidade.sh),
[resultados/verificacao-estabilidade.txt](../resultados/verificacao-estabilidade.txt)) disparou 50 requisições
simultâneas a cada endpoint do k6: 0 erros, 0 timeouts do pool, health `UP`. Com o cache vazio, as 50 requisições
ao `/com-cache` foram todas MISS (50 SQLs): o efeito manada que o cenário de partida a frio mede sob carga.
