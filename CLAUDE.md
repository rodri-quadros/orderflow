# Trabalho A2 — Análise e Otimização de Sistemas (UVA, Prof. André Lucio)

API REST (sem frontend) de pedidos, clientes, produtos e itens para demonstrar, com evidências medidas:
1. **Cache** com Redis (sem cache × com cache, TTL, invalidação).
2. **Consultas**: LAZY × EAGER, N+1, JOIN FETCH, SQL nativo/DTO e índices (EXPLAIN ANALYZE).
3. **Testes de carga** com k6 (média, p95, p99, throughput, erros; 10/50/100/200 VUs).

Fluxo: identificar o problema → implementar alternativa → medir → comparar → justificar.

## Fontes obrigatórias de consulta
- `docs/enunciado-a2.md` — requisitos oficiais do trabalho (o que precisa ser entregue e respondido).
- `docs/referencias-aulas.md` — padrões de código e vocabulário da disciplina (seguir nomes e estilo).
Em caso de dúvida, o enunciado prevalece; registre aqui qualquer divergência deliberada.

## Stack (versões efetivas)
Java 21 · Spring Boot 4.1.2 (Initializr) · Hibernate ORM 7.4.13 · Jakarta Persistence 3.2 · HikariCP 7.0.2 ·
PostgreSQL 17 (`postgres:17-alpine`) · Redis 8 (`redis:8-alpine`, cliente Lettuce 7.5) · Docker Compose · k6 · Maven Wrapper.

Atenção ao Boot 4: starter web é `spring-boot-starter-webmvc`; Jackson 3 (`tools.jackson.*`); confira nomes de
classes/propriedades nos jars antes de usar (não inventar APIs).

## Pacotes (`br.uva.pedidos`)
`config`, `controller`, `service`, `repository`, `entity`, `dto`, `exception`. Classe principal: `PedidosApplication`.

## Decisões já tomadas
- Cache com **Redis** (Spring Cache: `@Cacheable(value = "produtos", key = "#id")`, `@CacheEvict`), TTL por cache.
- `spring.jpa.open-in-view: false` — com OSIV o LAZY seria carregado na serialização e mascararia o N+1.
- `ddl-auto: validate`; schema e dados **só por SQL** em `db/init/` (`01_usuario_app.sh` → `02_schema.sql` → `03_dados.sql`).
- Usuário da aplicação (`APP_DB_USER`) só tem DML; DDL (tabelas, índices) é feito com o admin.
- Sem `default_batch_fetch_size` global (esconderia o N+1; batch fetching será variante estudada).
- Experimento EAGER usa entidade **`PedidoEager` separada e somente leitura** (`@Immutable`) mapeando a mesma tabela,
  para não contaminar as demais consultas.
- Header **`X-SQL-Count`** em toda resposta de `/api/**` com o nº de SQLs da requisição (`config.ContadorSql`, um
  `StatementInspector` com `ThreadLocal`, + `config.FiltroContadorSql`). Fonte da "quantidade de acessos ao banco".
- Volume: **100 mil pedidos** (≥ 10 mil exigidos no enunciado).
- Toda configuração em `.env` (lido pelo Compose e pelo Spring via `spring.config.import`); nenhum segredo versionado.
- `SQL_LOG_LEVEL=debug` nos experimentos de consulta; `info` nos testes de carga.
- Portas só em `127.0.0.1`; Postgres no host em `5433` (5432 ocupada por instalação local).
- **Datas sem conversão de fuso**: colunas `TIMESTAMP` (sem fuso) + `LocalDateTime`, e **sem** `hibernate.jdbc.time_zone`.
  Com `time_zone: UTC` o Hibernate deslocava -3 h (fuso da JVM) na gravação e na leitura, e a API divergia do psql.

## Banco de dados
- `db/init/02_schema.sql`: `cliente`, `produto`, `pedido`, `item_pedido` (PK identity).
- `db/init/03_dados.sql`: SQL puro, `setseed(0.42)`, data de referência fixa `2026-11-01` (não `now()`).
  Volumes (`\set` no topo): 10.000 clientes, 1.000 produtos (~10% inativos), 100.000 pedidos, ~300 mil itens (1–5 por pedido).
  Carga ≈ 9 s; duas recargas geram dados idênticos (md5 de todas as tabelas conferido).
- Distribuição desigual de pedidos por cliente (`power(random(), 1.5)`): cliente **1** tem 225 pedidos; cliente **545** é típico (9, a mediana).
- Índices: só PKs, `cliente.email` (UNIQUE) e `idx_item_pedido_pedido` (para o N+1 medir nº de consultas, não falta de índice).
  **Sem** índice em `pedido.cliente_id`/`data_pedido` de propósito: é o "antes" do experimento de índices.
- Entidades: todos os `@ManyToOne` e `Pedido.itens` são LAZY explícitos; sem `Cliente.pedidos`/`Produto.itens`.
  Itens persistem em cascata por `Pedido.adicionarItem` (sem repositório de item).
- Recarregar: `docker compose down -v && docker compose up -d`. Validar: `db/validacao_dados.sql` (saída em `resultados/volume-dados.txt`).

## API (Etapa 4)
| Método | Rota | Sucesso |
|---|---|---|
| POST | `/api/clientes` | 201 + Location |
| GET | `/api/clientes/{id}` | 200 |
| GET | `/api/clientes/{id}/pedidos?page&size` | 200 (`size` 1–100, ordem `dataPedido` DESC) |
| POST | `/api/produtos` | 201 + Location (`/{id}/sem-cache`) |
| GET | `/api/produtos/{id}/sem-cache` | 200 |
| PUT | `/api/produtos/{id}` | 200 |
| POST | `/api/pedidos` | 201 + Location |
| GET | `/api/pedidos/{id}` | 200 |
| PATCH | `/api/pedidos/{id}/status` | 200 |

Códigos de erro: 400 = Bean Validation, JSON malformado, enum inválido, tipo de parâmetro inválido;
404 = cliente/produto/pedido inexistente; 409 = transição de status inválida, email duplicado, violação de integridade;
422 = produto inativo ou repetido no pedido; 500 = genérico (stack trace só no log).
Erros sempre em `ProblemDetail` (`TratadorDeErros extends ResponseEntityExceptionHandler`), com `erros[{campo, mensagem}]` nos 400 de validação.

Decisões da Etapa 4:
- DTOs `record` em `dto` (`...Request` entrada, `...DTO` saída, fábrica estática `de(entidade)`); entidades nunca saem da API.
- `ProdutoService.buscarProduto(id)` → `ProdutoRepository.buscarDTO(id)` (constructor expression, 1 SQL). Na Etapa 5 o
  `@Cacheable` entra num método do service (cuidado com auto-invocação: chamar via proxy, não `this.`).
- `PedidoRepository.buscarResumosPorCliente(clienteId, Pageable)` → `List` (sem count), SQL `WHERE cliente_id=? ORDER BY data_pedido DESC FETCH FIRST ? ROWS`.
  A existência do cliente só é consultada se a lista vier vazia (caminho comum = 1 SQL).
- `PedidoRepository.buscarComItens(id)`: JOIN FETCH cliente + itens + produto (1 SQL), usado por GET e PATCH.
- Criação de pedido: `findAllById` uma vez + `Map<Long, Produto>` (2 SELECTs fixos); INSERT por item é inevitável com IDENTITY.
- Regra de status só em `StatusPedido.podeMudarPara`, aplicada por `Pedido.alterarStatus`.
- Sem `@Validated` na classe do controller: a validação nativa do Spring MVC trata `@Min/@Max` dos parâmetros
  (`HandlerMethodValidationException`); com `@Validated` o proxy AOP lançaria `ConstraintViolationException`.
- Sem conversão de fuso (ver "Decisões já tomadas").

## Cache (Etapa 5)
- `GET /api/produtos/{id}/sem-cache` → `ProdutoService.buscarProduto` (cenário A); `GET /api/produtos/{id}/com-cache` →
  `buscarProdutoComCache` com `@Cacheable(value = "produtos", key = "#id")` (cenário B). Ambos chamados direto pelo controller.
- `PUT /api/produtos/{id}` → `atualizar` com `@CacheEvict(value = "produtos", key = "#id")` (evict, não `@CachePut`).
- `config.CacheConfig`: `RedisCacheManager` com TTL `CACHE_TTL_PRODUTOS` (padrão 5m), sem nulos, serializador **tipado**
  `JacksonJsonRedisSerializer<>(ProdutoDTO.class)` (sem default typing), chave `produtos::{id}`, `disableCreateOnMissingCache`,
  `transactionAware`, `enableStatistics` e `immediateWrites` (no Spring Data Redis 4.1 o put/evict é **assíncrono por padrão**;
  síncrono garante que a chave já saiu quando o PUT responde).
- `@EnableCaching(order = HIGHEST_PRECEDENCE)`: proxy de cache por fora do `@Transactional` → HIT não abre transação nem
  pega conexão do pool (conferido no log do `JpaTransactionManager`); evict do PUT roda após o commit.
- `config.TratadorErroCache` (`CacheErrorHandler`): Redis fora → `warn` e segue para o banco (200, não 500).
  Timeout do Redis 500 ms: com Redis parado, GET com cache ≈ 1 s (get + put expiram), PUT ≈ 0,7 s.
- Criação de pedido lê preço com `findAllById` (banco), nunca do cache.
- Métricas: `/actuator/metrics/cache.gets?tag=result:hit|miss`, `cache.puts`, `cache.removals`.
- Experimento: `scripts/experimento-cache.sh` (API com `CACHE_TTL_PRODUTOS=10s SQL_LOG_LEVEL=info`) →
  `resultados/cache/experimento-cache.txt`. Restaura o preço e remove o pedido que cria; a base continua idêntica à da Etapa 3.
- O script também confere: corpo do HIT idêntico byte a byte ao `/sem-cache` (escala `788.60` preservada), 404 sem
  criar chave e `redis-cli MONITOR` (GET, SET ... PX, GET).

## Experimentos de persistência (Etapa 6)
- `entity.PedidoEager`: mesma tabela `pedido`, `@Immutable`, cliente e itens **EAGER** (`@OneToMany` unidirecional com
  `@JoinColumn(name = "pedido_id", insertable = false, updatable = false)`), `PedidoEagerRepository.findAllByOrderByIdAsc(Limit)`.
  `Pedido` (LAZY) continua sendo a entidade da API.
- `ExperimentoService` (`@Transactional(readOnly = true)`, `EntityManager` no estilo da aula) + `ExperimentoController`
  em `/api/experimentos/pedidos/{lazy,eager,eager/{id},join-fetch,nativa,resumo-lazy,resumo-eager}?limite=1..1000`.
  Todas devolvem os `limite` primeiros pedidos por id; LAZY, EAGER, JOIN FETCH e nativa geram JSON idêntico.
- SQLs observados (N pedidos, C clientes distintos): LAZY = EAGER em lista = 1 + N + C (1.937 com N=1000);
  `eager/{id}` = 1 (JOIN); JOIN FETCH = 2 (ids, depois `IN :ids`, para evitar paginação em memória HHH90003004);
  nativa = 1; resumo-lazy = 1 + C; resumo-eager = 1 + N + C (itens carregados sem uso).
- `item.getProduto().getId()` lê o id do proxy sem consulta (não foi preciso mapear `produto_id` à parte).
- `scripts/experimento-persistencia.sh`: sobe a própria API (jar, porta 18080 ou `PORTA_EXPERIMENTO`) com
  `SQL_LOG_LEVEL=info` para medir e com `debug` + log de parâmetros (`org.hibernate.orm.jdbc.bind=trace`) para as
  evidências; saída em `resultados/persistencia/` (CSV, TXT, `sql-*.txt`). A porta 8081 está ocupada nesta máquina.
- `StatementTimeoutTest`: `SHOW statement_timeout` = `10s` pela conexão da aplicação e `pg_sleep(11)` cancelado
  (deixa o `verify` cerca de 10 s mais lento).
- Coleção Postman: 47 requisições (pastas Clientes, Produtos, Cache, Experimentos, Pedidos).

## Índices (Etapa 7)
- **Estado padrão do banco: sem `idx_pedido_cliente_data` e sem `idx_pedido_cliente`** (só `pedido_pkey` em `pedido`).
  É o "antes" do experimento; nenhum índice extra entra em `db/init`.
- Alternar (como admin, pelo host; o `pedidos_app` não tem DDL):
  `set -a; . ./.env; set +a; PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -h 127.0.0.1 -p $POSTGRES_PORT -U $POSTGRES_ADMIN_USER -d $POSTGRES_DB -f db/indice/criar_indice.sql`
  (`remover_indice.sql` volta; `criar_indice_simples.sql`/`remover_indice_simples.sql` só para comparação).
- `db/indice/explain_pedidos_cliente.sql`: consultas A (SQL do Hibernate copiado do log, páginas 0 e 2), B (enunciado)
  e C (slide, intervalo), separadas por `-- consulta:`; uso manual com `-v cliente=1`.
- `scripts/experimento-indice.sh`: estados sem → simples → composto → sem_final (controle de aquecimento da JVM);
  planos em `resultados/explain/`, CSV/TXT em `resultados/indice/`; inserção de 10 mil pedidos em `BEGIN ... ROLLBACK`
  com ids explícitos + `VACUUM` entre execuções; mede também o WAL gerado; termina com `VACUUM FULL pedido` +
  `VACUUM ANALYZE` (tamanho físico original). Verificação da Etapa 6 numa porta +10, com `PULAR_EMPACOTAMENTO=1`.
- Resultado: cliente 1 página 0 com Index Scan sem Sort (0,054 ms, 26 buffers) × Seq Scan + top-N heapsort (3,5–4,8 ms,
  907 buffers); B, C e cliente 545 usam Bitmap Heap Scan + Sort mesmo com o composto (decisão de custo, explicada no README).
  Índice composto 3,1 MB (43% da tabela), +33% de WAL na inserção; `idx_scan` +4 com 4 chamadas à API.
- `X-SQL-Count` de `/api/clientes/{id}/pedidos` é 1 (2 só quando a página vem vazia: confere a existência do cliente).

## Testes (Etapa 8)
- `./mvnw clean verify` → 87 testes (1 pulado), ~17 s. **A camada 2 precisa do Compose no ar** (PostgreSQL e Redis reais;
  sem Testcontainers). Teste lento (`pg_sleep(11)`) só com `-Dtestes.lentos=true` (`@EnabledIfSystemProperty`).
- Camada 1 (`test/.../entity`, `.../service`): JUnit 6 + AssertJ + Mockito, sem Spring. Camada 2 (`test/.../controller`):
  `@SpringBootTest` + `@AutoConfigureMockMvc` (Boot 4: `org.springframework.boot.webmvc.test.autoconfigure`), base
  `TesteIntegracao` com helpers (`get/post/put/patch`, `sqlCount`, `assertSemDadosInternos`, `pedidoJson`, `item`).
- **Ids de teste só em `test/.../DadosTeste.java`**: clientes 1 (225 pedidos) e 545 (9); produtos ativos 10 (1419.87) e
  20 (1236.44), inativo 5; produto 40 reservado ao cache; pedidos 3 (PENDENTE) e 1 (APROVADO); inexistente 999999.
- Escrita: `@Transactional` (rollback). Cache: sem transação (evict após commit), restaura em `@AfterEach`.
- `scripts/verificacao-estabilidade.sh`: 50 requisições simultâneas por endpoint do k6, sobe a própria API (18080).
  Mostrou cache stampede: 50 MISS simultâneos com cache vazio (`@Cacheable` sem `sync`).
- `docs/checklist-requisitos.md`: requisito do enunciado → evidência → status (pendências das Etapas 9–11).

## Testes de carga (Etapa 9)
- k6 v2.4.0 nativo (`/usr/bin/k6`, apt). Scripts em `k6/` (`lib/config.js`, `cache.js`, `persistencia.js`, `indice.js`;
  `k6/dados/produtos-ativos.json` = 901 ids). `constant-vus`, sem think time, `discardResponseBodies`.
- Rodar: `scripts/rodar-cenarios.sh [cache|persistencia|indice|todos]` (~50 + ~46 + ~23 min; rodar em blocos).
  Variáveis: `NIVEIS`, `DURACAO`, `AQUECIMENTO`, `REPETICOES`, `AQUECIMENTO_INICIAL`, `PORTA_EXPERIMENTO` (18080), `DIR_SAIDA`.
  Sobe a própria API (jar). Saída: `resultados/carga/<cenario>/<alvo>/vus<N>_rep<R>{.json,_amostras.csv,_metricas.json}`.
- Gráficos: `python3 -m venv .venv && .venv/bin/pip install -r scripts/requirements.txt && .venv/bin/python scripts/gerar_graficos.py`
  → `resultados/carga/resumo.{csv,md}` e `resultados/graficos/*.png`. Nenhum número digitado à mão.
- `GET /api/produtos/{id}/com-cache-sync` (`@Cacheable(sync = true)`): no Spring Data Redis 4.1 com writer sem trava,
  **sync não sincroniza** (conferido no bytecode: sem monitor nem lock); só `enableLocking()` trava, e a trava é
  distribuída (`produtos~lock`) e vale para o cache inteiro. Mantido como achado.
- Estatísticas do PostgreSQL publicadas com atraso de até 10 s: o script espera 11 s após cada rodada; deltas do banco
  analisados por transação.

## Relatório e estado final (Etapa 10)
- **Todas as etapas técnicas concluídas**; falta só a Etapa 11 (vídeo de até 7 min, commit e entrega).
- `README.md` = relatório da seção 7.2, nas seções 1–7 do enunciado + 8 (reproduzir) + 9 (estrutura); ~890 linhas,
  ~20 min de leitura. **Nomes e matrículas dos alunos nunca entram em arquivo versionado** (só em `apresentacao/`, ignorada).
- Detalhes longos fora do README: `docs/apendice-experimentos.md` (passo a passo do cache, tabela completa da
  Etapa 6, os 32 planos, Lei de Little, checagem frio × HIT, testes por classe) e `docs/decisoes-tecnicas.md`
  (decisões com motivo). `resultados/carga/analise-preliminar.md` é histórico da Etapa 9.
- `docs/checklist-requisitos.md`: requisito → seção do README → evidência.
- `scripts/conferir_numeros.py [--prosa] [arquivos]`: confere se cada número das tabelas existe em `resultados/`
  (formato brasileiro, arredondamento pelas casas exibidas); razões "×"/"vezes" saem como "derivado" para
  conferência manual. Rodar depois de qualquer mudança de número no README.
- `scripts/rodar-cenarios.sh checagem` (~7 min): HIT e partida a frio intercalados, 100 VUs →
  `resultados/carga/checagem-frio-hit/` (fora do glob do resumo principal). Resultado: HIT 14.618 × frio
  13.742 req/s; a vantagem do frio na bateria principal era efeito de ordem/temperatura.
- Ao mudar números: copiar de `resultados/` (nunca digitar), regenerar com `gerar_graficos.py` e rodar o conferidor.
- Mermaid do README revisado à mão (renderizar com `mermaid-cli` exigiria baixar pacote e rodar o Chrome).

## Entrega e vídeo (Etapa 11)
- Remoto: `origin` (branch `main`, ver `git remote -v`). Não reescrever histórico já publicado.
- `apresentacao/` (ignorada pelo git): `abertura.html`, `encerramento.html` (palco 1920×1080 escalado) e
  `roteiro-video.md`. Nomes e matrículas só lá.
- `scripts/demo-video.sh`: demonstração com pausas (cache, N+1, índices, k6 50 VUs × 15 s); usa a API da 8080,
  reverte o PUT (inclusive por `trap`), termina sem índice, Redis vazio. ~45 s sem as pausas
  (testar com `yes '' | scripts/demo-video.sh`).
- `./mvnw spring-boot:run` roda com `-XX:TieredStopAtLevel=1` (só C1): para números sob carga, usar o jar
  (`java -jar target/trabalho-a2-0.0.1-SNAPSHOT.jar`); no teste, k6 com índice: 3.422 (run) × 5.586 req/s (jar).
- Reprodução do zero (clone + `.env` novo) funcionou. Achados corrigidos no README, seção 8: "healthy" aparece antes
  do fim do `03_dados.sql` (esperar "PostgreSQL init process complete" no log); faltava o comando do checksum;
  `spring-boot:run` ocupa o terminal (verify antes da API). O nome de projeto do Compose é fixo (`trabalho-a2`):
  para uma segunda cópia, `COMPOSE_PROJECT_NAME=<outro>` antes de qualquer `docker compose` (senão o `down -v`
  da cópia apaga o volume original).

## Divergências deliberadas em relação às aulas
- Aula: `buscarProduto` é o método com `@Cacheable` e `invalidarCache(id)` é um método separado com `@CacheEvict`.
  Aqui: `buscarProduto` = sem cache (A), `buscarProdutoComCache` = com cache (B), e o `@CacheEvict` fica no próprio
  `atualizar` (um `this.invalidarCache()` dentro do service ignoraria o proxy e não invalidaria nada).
- `buscarDTO` retorna `Optional<ProdutoDTO>` (para responder 404), não `ProdutoDTO`.
- JOIN FETCH via `@Query` no repositório em vez de `entityManager.createQuery` (mesma JPQL).

## Regras de código
- Simplicidade e legibilidade acima de sofisticação; nada que não sirva aos requisitos do trabalho.
- Domínio em português, seguindo a disciplina: `Pedido`, `Cliente`, `Produto`, `ItemPedido`, `ProdutoService`, `ProdutoDTO`, `buscarDTO`.
- Comentários só para explicar um "porquê" não óbvio.
- Sem abstrações, interfaces ou dependências sem uso real. Sem Lombok.
- Configuração externalizada; nenhum segredo no código.

## Comandos
```bash
cp .env.example .env            # e troque as senhas
docker compose up -d            # sobe postgres e redis
docker compose ps               # ambos devem ficar "healthy"
./mvnw spring-boot:run          # API em http://127.0.0.1:8080
curl -s localhost:8080/actuator/health
./mvnw clean verify             # contextLoads precisa do Compose no ar
docker compose down             # para (mantém dados)
docker compose down -v          # apaga o volume; init scripts rodam de novo no próximo up
```
