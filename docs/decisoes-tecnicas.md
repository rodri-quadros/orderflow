# Decisões técnicas

Registro das decisões que não cabem no [README](../README.md), com o motivo de cada uma. Os números citados vêm
dos arquivos de [resultados/](../resultados/).

## Ambiente e configuração

| Decisão | Motivo |
|---|---|
| Toda configuração em `.env` (lido pelo Compose e pelo Spring via `spring.config.import`); `.env.example` versionado | nenhum segredo no repositório; o mesmo arquivo serve aos dois |
| Portas publicadas só em `127.0.0.1`; PostgreSQL no host em `5433` | nada exposto na rede; a 5432 estava ocupada por uma instalação local |
| Usuário da aplicação (`APP_DB_USER`) só com DML; DDL (tabelas, índices) feita pelo admin | menor privilégio: a API não consegue criar nem apagar estruturas |
| `spring.jpa.open-in-view: false` | com OSIV, o LAZY seria carregado durante a serialização e mascararia o N+1 |
| `ddl-auto: validate`; schema e dados só por SQL em `db/init/` | o mapeamento é conferido na subida, e a base é reproduzível |
| Colunas `TIMESTAMP` (sem fuso) + `LocalDateTime`, sem `hibernate.jdbc.time_zone` | com `time_zone: UTC`, o Hibernate deslocava 3 h na gravação e na leitura, e a API divergia do `psql` |
| Pool Hikari de 10 conexões, `connection-timeout` 5 s, `statement_timeout` 10 s | valores padrão conhecidos; o timeout impede consultas presas (conferido por `StatementTimeoutTest`) |
| `SQL_LOG_LEVEL=debug` nas evidências de SQL, `info` nas medições | o log de cada SQL distorceria o tempo medido |
| Header `X-SQL-Count` em toda resposta de `/api/**` (`ContadorSql`, um `StatementInspector` com `ThreadLocal`, + `FiltroContadorSql`) | conta as idas ao banco por requisição sem depender de log |

## Banco de dados

- **Carga determinística:** `setseed(0.42)` e data de referência fixa (`2026-11-01`, não `now()`). Duas recargas
  geram tabelas idênticas (md5 conferido). Checksum: `100000 | 1545590410.75` (contagem e soma de
  `valor_total` dos pedidos).
- **Distribuição desigual de pedidos por cliente** (`power(random(), 1.5)`): o cliente 1 tem 225 pedidos e o
  545 tem 9 (a mediana). As duas pontas mostram como a seletividade muda o plano.
- **Índices iniciais:** só as PKs, `cliente.email` (UNIQUE) e `idx_item_pedido_pedido`. O último existe para que o
  experimento de N+1 meça a quantidade de consultas e não a falta de índice. `pedido.cliente_id` e
  `data_pedido` ficam sem índice: é o "antes" do experimento de índices.
- **Limitação conhecida:** as datas de pedido e de cadastro foram sorteadas de forma independente, então alguns
  pedidos têm data anterior ao cadastro do cliente, e um pedido gerado pode repetir um produto. A API não permite
  isso em pedidos novos. Nenhum dos dois casos afeta as medições.

## API

- **DTOs `record`** (`...Request` na entrada, `...DTO` na saída, com fábrica `de(entidade)`); entidades nunca saem
  da API.
- **Erros em `ProblemDetail`** (RFC 9457), por `TratadorDeErros extends ResponseEntityExceptionHandler`:
  400 (Bean Validation, JSON malformado, enum ou tipo inválido, com a lista `erros[{campo, mensagem}]`),
  404 (recurso inexistente), 409 (transição de status inválida, email duplicado, violação de integridade),
  422 (produto inativo ou repetido no pedido), 500 genérico (detalhe só no log).
- **Sem `@Validated` na classe do controller:** a validação nativa do Spring MVC trata `@Min/@Max` dos
  parâmetros (`HandlerMethodValidationException`); com `@Validated`, o proxy AOP lançaria outra exceção.
- **Criação de pedido:** `findAllById` uma vez + `Map<Long, Produto>` (2 SELECTs fixos para N itens). O INSERT por
  item é inevitável com chave `IDENTITY`.
- **Pedidos do cliente:** lista sem `count` (`WHERE cliente_id = ? ORDER BY data_pedido DESC FETCH FIRST ? ROWS`).
  A existência do cliente só é consultada se a página vier vazia, então o caminho comum faz 1 SQL.
- **`GET /api/pedidos/{id}`:** `JOIN FETCH` de cliente, itens e produto em 1 SQL.

## Cache

- **Evict, não `@CachePut`, no PUT:** a próxima leitura busca o valor do banco já commitado.
- **`@EnableCaching(order = HIGHEST_PRECEDENCE)`:** o proxy de cache fica por fora do `@Transactional`. Um HIT não
  abre transação nem pega conexão do pool (conferido no log do `JpaTransactionManager`), e o evict roda depois do
  commit.
- **`transactionAware()` + `immediateWrites()`:** no Spring Data Redis 4.1, put e evict são assíncronos por padrão.
  Síncronos, a chave antiga já saiu quando o PUT responde.
- **Serializador tipado `JacksonJsonRedisSerializer<>(ProdutoDTO.class)`:** sem default typing, ninguém consegue
  forçar a desserialização de outra classe gravando no Redis. O JSON fica legível no `redis-cli`.
- **`CacheErrorHandler` (`TratadorErroCache`):** Redis fora → aviso no log e consulta ao banco (200, não 500).
  Timeout do Redis de 500 ms: com o Redis parado, uma consulta com cache leva cerca de 1 s e um PUT cerca de 0,7 s.
- **`sync = true` mantido como achado:** nesta versão, sem `enableLocking()`, ele não sincroniza (detalhes no
  [apêndice A](apendice-experimentos.md#por-que-sync--true-não-sincroniza-nesta-versão)). Ligar a trava
  distribuída serializaria todas as leituras do cache, não só as da mesma chave.

## Persistência

- **`PedidoEager` separada e `@Immutable`** sobre a mesma tabela: um mapeamento JPA só aceita um `FetchType`, e
  mudar o `Pedido` afetaria todas as consultas da API.
- **JOIN FETCH em dois passos** (ids, depois `IN :ids`): um JOIN FETCH de coleção com `setMaxResults` faria o
  Hibernate paginar em memória (aviso `HHH90003004`), lendo a tabela inteira.
- **Sem `default_batch_fetch_size` global:** esconderia o N+1 que o experimento mostra.
- **`item.getProduto().getId()`** lê o id do proxy sem consulta; não foi preciso mapear `produto_id` à parte.

## Testes de carga

- **k6 nativo no host** (apt, repositório oficial), `constant-vus`, sem think time, `discardResponseBodies`.
- **A API dos testes sobe pelo próprio script** (jar, porta 18080, log `info`), separada de qualquer API de
  desenvolvimento na 8080. A 8081 está ocupada nesta máquina.
- **Espera de 11 s após cada rodada:** o PostgreSQL publica as estatísticas de backends ociosos com atraso de até
  10 s; sem a espera, a cauda de uma rodada vazaria para a próxima. Os deltas do banco são lidos por transação.
- **Última amostra de cada rodada descartada** no resumo: cai depois do fim do k6 e mistura carga e ociosidade.
- **Nenhum número digitado à mão:** `resumo.csv`, `resumo.md` e os gráficos saem de `scripts/gerar_graficos.py`.

## Divergências deliberadas em relação às aulas

| Aula | Aqui | Motivo |
|---|---|---|
| `buscarProduto` com `@Cacheable`; `invalidarCache(id)` separado com `@CacheEvict` | `buscarProduto` = sem cache (cenário A), `buscarProdutoComCache` = com cache (B); `@CacheEvict` no próprio `atualizar` | o enunciado pede as duas versões; um `this.invalidarCache()` dentro do service ignoraria o proxy e não invalidaria nada |
| `buscarDTO` retorna `ProdutoDTO` | retorna `Optional<ProdutoDTO>` | para responder 404 |
| JOIN FETCH com `entityManager.createQuery` | `@Query` no repositório na API; `EntityManager` nos experimentos | mesma JPQL, no estilo do Spring Data |
