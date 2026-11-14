# Checklist de requisitos — Trabalho A2

Mapeia cada requisito e cada pergunta obrigatória de [enunciado-a2.md](enunciado-a2.md) para a seção do
[README](../README.md) que o atende e para a evidência no repositório. Status: **atendido**, ou **preparado** no
caso do vídeo, que é gravado pelo grupo.

Atualizado na Etapa 11.

## Seção 2 — Características gerais da aplicação

| Requisito | README | Evidência | Status |
|---|---|---|---|
| Web Services REST, sem frontend | 2.5 | `src/main/java/br/uva/pedidos/controller/`; `postman/A2.postman_collection.json` | atendido |
| Banco relacional | 2.2, 2.4 | PostgreSQL 17 (`docker-compose.yml`) | atendido |
| ≥ 3 tabelas relacionadas | 2.4 | `db/init/02_schema.sql` (cliente, produto, pedido, item_pedido); diagrama ER | atendido |
| Endpoints de consulta | 2.5 | `GET /api/clientes/{id}`, `/pedidos`, `/api/produtos/{id}/sem-cache`, `/api/pedidos/{id}` | atendido |
| ≥ 1 operação de atualização (para o cache) | 2.5, 3.2 | `PUT /api/produtos/{id}` (invalida o cache), `PATCH /api/pedidos/{id}/status` | atendido |
| Estratégias diferentes de recuperação | 2.5, 4.1, 4.2 | `/api/experimentos/pedidos/*`; `/sem-cache` × `/com-cache` | atendido |
| 2.1 Tecnologias | 2.2 | Java 21, Spring Boot 4.1.2, Hibernate 7.4, PostgreSQL 17, Redis 8 | atendido |
| 2.2 Domínio simples | 1, 2.4 | pedidos, clientes, produtos e itens | atendido |
| 2.3 Entidade principal ≥ 10.000 registros, carga por script | 2.4 | `db/init/03_dados.sql` (100.000 pedidos, `setseed`); `resultados/volume-dados.txt` | atendido |

## Seção 3 — Item 1: cache

| Requisito | README | Evidência | Status |
|---|---|---|---|
| 3.1 Escolha e justificativa do dado cacheável (5 critérios) | 3.1 | tabela de critérios | atendido |
| 3.2 Cenário A (sem cache) e B (com cache) | 3.2 | `ProdutoService`, `ProdutoController` | atendido |
| 3.3 Tecnologia explicada e justificada | 3.3 | `config/CacheConfig.java` | atendido |
| 3.4 TTL configurado e demonstrado | 3.4, 3.5 | `CACHE_TTL_PRODUTOS`; passo 5 do experimento | atendido |
| 3.4 Estratégia contra dado desatualizado | 3.4 | `@CacheEvict` após o commit, síncrono; `CacheIntegracaoTest` | atendido |
| 3.4 Experimento obrigatório (passos 1 a 5) | 3.5 | `scripts/experimento-cache.sh` → `resultados/cache/experimento-cache.txt` | atendido |
| 3.4 Uso temporário de dado desatualizado e riscos | 3.5, 3.8 (questão 3) | escrita direta no banco no experimento | atendido |
| 3.5 Tempo de resposta com e sem cache | 3.6, 3.7 | experimento (1 usuário) e cenário 1 do k6 | atendido |
| 3.5 Acessos ao banco | 3.5, 3.7 | `X-SQL-Count`; transações por requisição | atendido |
| 3.5 Hit e miss; efeito do TTL; invalidação | 3.5, 3.7 | experimento; HIT, MISS contínuo e partida a frio sob carga | atendido |
| 3.5 Questões 1 a 4 | 3.8 | respostas numeradas, com os números de carga | atendido |

## Seção 4 — Item 2: LAZY × EAGER e consultas

| Requisito | README | Evidência | Status |
|---|---|---|---|
| 4.1 Operação LAZY e momento das consultas adicionais | 4.1 | `/lazy`; `resultados/persistencia/sql-lazy.txt` | atendido |
| 4.1 Demonstração do N+1 | 4.1 | `sql-lazy.txt`; `ExperimentoControllerTest` | atendido |
| 4.2 Versão EAGER equivalente e comportamento observado | 4.1 | `entity/PedidoEager.java`; `sql-eager.txt`, `sql-eager-por-id.txt` | atendido |
| 4.3 Comparação com quantidades diferentes (SQLs, tempo, volume, dados desnecessários, N+1) | 4.1 | `persistencia.txt` (10, 100 e 1000 pedidos); grid; [apêndice B](apendice-experimentos.md#b-lazy-eager-e-consultas-otimizadas-tabela-completa) | atendido |
| 4.3 Quando usar LAZY ou EAGER | 4.1 ("Quando usar LAZY ou EAGER (enunciado 4.3)") | — | atendido |
| 4.4 ≥ 1 otimização implementada e comparada | 4.2 | JOIN FETCH em 2 passos e SQL nativo, isolado e sob carga | atendido |
| 4.4 SQL nativo: ganho real, manutenção e portabilidade | 4.2 ("O SQL nativo trouxe benefícios reais? (enunciado 4.4)") | — | atendido |

## Seção 5 — Item 2: índices

| Requisito | README | Evidência | Status |
|---|---|---|---|
| 5.1 Consulta com filtro, ordenação e intervalo | 4.3 | `db/indice/explain_pedidos_cliente.sql` | atendido |
| 5.2 Execução sem e com índice | 4.3 | `scripts/experimento-indice.sh` (sem → simples → composto → sem) | atendido |
| 5.2 Uso de outros índices no plano | 4.3 ("Observado, não presumido") | `resultados/explain/*.txt`; [apêndice C](apendice-experimentos.md#c-índices-todos-os-planos) | atendido |
| 5.3 EXPLAIN ANALYZE: varreduras, ordenação, linhas, tempo | 4.3 | tabela de planos; `resultados/indice/indice.csv` | atendido |
| 5.4 Perguntas 1 a 5 | 4.3 ("Respostas da seção 5.4 do enunciado") | — | atendido |

## Seção 6 — Item 3: testes de desempenho

| Requisito | README | Evidência | Status |
|---|---|---|---|
| 6.1 Ferramenta apresentada e justificada | 5.1 | `k6/` | atendido |
| 6.2 Cenário 1 — cache (preenchido e vazio) | 3.7, 5.2 | `k6/cache.js` | atendido |
| 6.2 Cenário 2 — LAZY, EAGER e otimizada | 4.2, 5.2 | `k6/persistencia.js` | atendido |
| 6.2 Cenário 3 — índices | 4.3, 5.2 | `k6/indice.js` | atendido |
| 6.3 Cargas de 10, 50, 100 e 200 VUs, duração suficiente | 5.2 | `scripts/rodar-cenarios.sh` (132 rodadas) | atendido |
| 6.4 Latência média, p95, p99, throughput e erros | 5.5 | `resultados/carga/resumo.md` | atendido |
| 6.4 CPU, memória e comportamento do banco | 5.4, 6.1 (questão 5) | `*_amostras.csv`, `*_metricas.json` | atendido |
| 6.5 Cuidados na execução | 5.3 | `resultados/carga/ambiente.txt`; checagem da partida a frio (5.4) | atendido |
| 6.6 Tabelas e gráficos comparativos | 3.7, 4.2, 4.3, 5.5 | 10 gráficos em `resultados/graficos/` | atendido |
| 6.7 Discussão (7 perguntas) | 6.1 | gargalos, Lei de Little, consistência, trade-offs e limitações (6.1 a 6.3) | atendido |

## Seção 7 — Entregáveis

| Requisito | README | Evidência | Status |
|---|---|---|---|
| 7.1 Código dos Web Services | 2.3, 9 | `src/main/java/` | atendido |
| 7.1 Configurações | 8 | `application.yml`, `docker-compose.yml`, `.env.example` | atendido |
| 7.1 Scripts de criação e população do banco | 2.4, 8 | `db/init/`, `db/indice/`, `db/validacao_dados.sql` | atendido |
| 7.1 Implementações alternativas | 3.2, 4.1, 4.2 | `ExperimentoService`, `PedidoEager`, `/sem-cache` × `/com-cache` | atendido |
| 7.1 Scripts dos testes de desempenho | 5, 8 | `k6/`, `scripts/rodar-cenarios.sh`, `scripts/gerar_graficos.py` | atendido |
| 7.1 Instruções para executar e reproduzir | 8 | — | atendido |
| 7.2 README: 1. Introdução | 1 | — | atendido |
| 7.2 README: 2. Arquitetura e tecnologias | 2 | diagramas Mermaid (arquitetura e ER) | atendido |
| 7.2 README: 3. Implementação de cache | 3 | — | atendido |
| 7.2 README: 4. Otimização das consultas | 4 | — | atendido |
| 7.2 README: 5. Testes de desempenho | 5 | — | atendido |
| 7.2 README: 6. Discussão | 6 | — | atendido |
| 7.2 README: 7. Conclusão | 7 | — | atendido |
| 7.2 Gráficos, tabelas, trechos de código e evidências | 3 a 5 | `scripts/conferir_numeros.py` confere os números das tabelas | atendido |
| 7.3 Apresentação / vídeo de até 7 min | 8 | `scripts/demo-video.sh` (cache, N+1, índices e k6 ao vivo), coleção Postman; roteiro e telas fora do repositório | preparado (gravação pelo grupo) |

## Seção 9 — Pergunta central

| Requisito | README | Status |
|---|---|---|
| "Como demonstrar, por meio de evidências, que uma mudança realmente melhorou o desempenho de um sistema?" | 1 (método) e 7 (resposta) | atendido |

## Qualidade (além do enunciado)

| Item | README | Evidência | Status |
|---|---|---|---|
| Testes automatizados de regras, API, cache e persistência | 5.6 | `src/test/java/` (87 testes); [apêndice E](apendice-experimentos.md#e-testes-funcionais-por-classe) | atendido |
| Ambiente estável antes da carga | apêndice E | `scripts/verificacao-estabilidade.sh` → `resultados/verificacao-estabilidade.txt` | atendido |
| Decisões técnicas registradas | 2.7 | [decisoes-tecnicas.md](decisoes-tecnicas.md) | atendido |
