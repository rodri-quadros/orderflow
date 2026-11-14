# Referências das aulas — Análise e Otimização de Sistemas (Prof. André Lucio)

Transcrição dos trechos de código e conceitos das apresentações usados como padrão no Trabalho A2.
As aulas de Programação Dinâmica e Algoritmos Gulosos têm exemplos em Python e servem apenas de base conceitual.

## Tópicos Extras — Cache

Arquitetura apresentada: Client → API → Redis Cache (hit retorna direto; miss segue) → Backend Service → Postgres.

```java
@Service
public class ProdutoService {

    @Cacheable(value = "produtos", key = "#id")
    public ProdutoDTO buscarProduto(Long id) {
        return produtoRepository.buscarDTO(id);
    }

    @CacheEvict(value = "produtos", key = "#id")
    public void invalidarCache(Long id) {
        // Remove a entrada armazenada
    }
}
```

Quando o cache ajuda: dados muito acessados, baixa ou média volatilidade, mais leituras que escritas, consultas custosas.
Cuidados: dado pode ficar desatualizado, cache não substitui o banco, é preciso definir expiração e invalidação.
Invalidação: ao atualizar um cadastro, ao alterar preço, ao confirmar um pedido.

| Dados (exemplos) | Volatilidade | TTL sugerido |
|---|---|---|
| Países e estados | muito baixa | 24 horas |
| Categorias de produtos | baixa | 30–60 min |
| Catálogo de preços | média | 1–5 min |
| Estoque | alta | segundos ou por evento |
| Saldo bancário | muito alta | evitar cache como fonte de decisão |

Tecnologias: Redis (cache em memória, distribuído, TTL), Caffeine (local, uma instância), Hazelcast, Infinispan.
Perguntas de debate: "Toda informação deveria ir para o cache?", "Como definir o TTL ideal?", "Em um sistema com várias instâncias, um cache local é suficiente?"

## Tópicos Extras — LAZY, EAGER e N+1

```java
@Entity
public class Pedido {

    @OneToMany(
        mappedBy = "pedido",
        fetch = FetchType.LAZY
    )
    private List<Item> itens;
}
```

O `FetchType.LAZY` controla quando o relacionamento é carregado no backend: `pedidoRepository.findById(1L)` pode não buscar os itens; acessar `pedido.getItens()` faz o Hibernate consultar o banco para inicializar a coleção.

Exemplo de N+1:

```java
// Relacionamento configurado como LAZY
@ManyToOne(fetch = FetchType.LAZY)
private Cliente cliente;

List<Pedido> pedidos = pedidoRepository.findAll();   // 1 consulta
for (Pedido p : pedidos) {
    System.out.println(p.getCliente().getNome());    // N consultas: SELECT * FROM cliente WHERE id = ?
}
// Resultado: 1 + N consultas
```

Solução com JOIN FETCH (1 consulta):

```java
List<Pedido> pedidos = entityManager.createQuery(
    "SELECT p FROM Pedido p JOIN FETCH p.cliente",
    Pedido.class
).getResultList();
// SELECT p.*, c.* FROM pedido p JOIN cliente c ON c.id = p.cliente_id
```

Resumo da aula: usar LAZY como padrão e optar por EAGER (ou JOIN FETCH) apenas quando o relacionamento for sempre necessário e tiver baixo impacto no volume de dados.
Reflexão: em um grid de pedidos (pedido, cliente, valor, botão Detalhes), trazer a lista e os detalhes em uma única query?

## Tópicos Extras — Code smell de acesso repetitivo

```java
List<PedidoDTO> resultado = new ArrayList<>();
for (Pedido p : pedidos) {
    Cliente c = clienteRepo.buscarPorId(p.getClienteId());       // consulta em cada iteração
    List<Item> itens = itemRepo.buscarPorPedido(p.getId());      // consulta em cada iteração
    resultado.add(montarDTO(p, c, itens));
}
// 1 + 2N consultas (1.000 pedidos → 2.001 consultas)
```

Possível solução: buscar em lote e reutilizar em memória (2 ou 3 consultas).

```java
List<Cliente> clientes = clienteRepo.buscarPorIds(idsClientes);
List<Item> itens = itemRepo.buscarPorPedidos(idsPedidos);

for (Pedido p : pedidos) {
    Cliente c = mapaClientes.get(p.getClienteId());
    List<Item> itensPedido = mapaItens.get(p.getId());
    resultado.add(montarDTO(p, c, itensPedido));
}
```

## Tópicos Extras — JPQL vs SQL nativo

ORM (JPA/JPQL) = mais produtividade; SQL nativo = mais controle.
Quando pensar em query nativa: consultas analíticas complexas, recursos específicos do banco, maior controle sobre joins e agregações, comparar SQL gerado e plano de execução.
Pergunta de debate: "Query nativa é sempre mais rápida?"

## Tópicos Extras — Índices

```sql
SELECT * FROM pedido
WHERE cliente_id = 150
  AND data_pedido >= '2026-01-01'
ORDER BY data_pedido DESC;

CREATE INDEX idx_pedido_cliente_data
ON pedido (cliente_id, data_pedido DESC);
```

Sem índice: mais leitura de páginas, table scan. Com índice: menos leitura, localiza melhor os registros.
Validar com EXPLAIN, EXPLAIN ANALYZE, tempo real da consulta e impacto em escrita (índices encarecem INSERT/UPDATE/DELETE).
Pergunta de debate: "Criar índice em toda coluna consultada é uma boa ideia?"

## Tópicos Extras — Testes de desempenho

Objetivo: avaliar o comportamento sob carga controlada, identificar gargalos e validar requisitos.
Observar: latência, p95 e p99, throughput, taxa de erros, CPU e memória, banco e conexões.
Tipos: carga (load), estresse (stress), pico (spike), resistência (soak), escalabilidade.
Como executar: definir objetivo (ex.: p95 < 500 ms) → criar cenário → executar a carga (subida gradual ou pico) → coletar métricas → analisar gargalos.
"Melhorar a média não basta; observe também a cauda da latência."
Ferramentas: JMeter (interface gráfica), k6 (testes por código em JavaScript, CI/CD), Gatling, Locust (Python).

```javascript
http.get('/api/produtos/10');
```

Perguntas de debate: "Um sistema com throughput alto pode ainda assim dar uma experiência ruim?", "Qual métrica pesa mais: throughput ou p99?"

## Tópicos Extras — Gargalos e refatoração

Fan-out: quantidade de componentes/dependências que um componente aciona para completar uma operação.
Sinais de gargalo: latência cresce com o número de chamadas, fila em componente central, CPU baixa com alta espera por I/O.
Throughput: quantidade de trabalho processado por unidade de tempo.

## Base conceitual (Programação Dinâmica e Gulosos)

- Memoization: armazenar o resultado de um subproblema e reutilizar quando ele reaparece (mesma ideia do cache: chave → valor já calculado).
- Fibonacci recursivo O(2ⁿ) → com memoization O(n): reduzir trabalho repetido muda a ordem de grandeza do custo (análogo a N+1 → consulta única).
- Algoritmo guloso: a melhor escolha local nem sempre produz a melhor solução global (análogo a otimizações que melhoram um ponto e pioram outro, como EAGER ou índices em excesso).
