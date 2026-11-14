# Trabalho A2 — Análise e Otimização de Sistemas (UVA, Prof. André Lucio)

API REST (sem frontend) de pedidos, clientes, produtos e itens para demonstrar, com evidências medidas:
1. **Cache** com Redis (sem cache × com cache, TTL, invalidação).
2. **Consultas**: LAZY × EAGER, N+1, JOIN FETCH, SQL nativo/DTO e índices (EXPLAIN ANALYZE).
3. **Testes de carga** com k6 (média, p95, p99, throughput, erros; 10/50/100/200 VUs).

Fluxo: identificar o problema → implementar alternativa → medir → comparar → justificar.

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
- Header de resposta **`X-SQL-Count`** com o nº de SQLs da requisição (via `StatementInspector`, etapa futura).
- Volume: **100 mil pedidos** (≥ 10 mil exigidos no enunciado).
- Toda configuração em `.env` (lido pelo Compose e pelo Spring via `spring.config.import`); nenhum segredo versionado.
- `SQL_LOG_LEVEL=debug` nos experimentos de consulta; `info` nos testes de carga.
- Portas só em `127.0.0.1`; Postgres no host em `5433` (5432 ocupada por instalação local).

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
