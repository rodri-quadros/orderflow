**Universidade Veiga de Almeida**

**Análise e Otimização de Sistemas**

**Professor: André Lucio**

**TRABALHO PRÁTICO (A2)**

## Tema: Otimização de Web Services por meio de Cache, Consultas ao Banco de Dados e Testes de Desempenho

### 1. Objetivo

O objetivo deste trabalho é aplicar, de forma prática, técnicas de otimização de sistemas, avaliando seus efeitos sobre o desempenho de uma aplicação baseada em Web Services.

Os alunos deverão desenvolver uma aplicação simples, composta por um ou mais Web Services que realizem operações de consulta e atualização em um banco de dados relacional.

A partir dessa aplicação, deverão implementar e avaliar três aspectos fundamentais de otimização:

1. **Utilização de cache:** reduzir acessos desnecessários ao banco de dados por meio de mecanismos de armazenamento temporário de informações.
2. **Otimização de consultas ao banco de dados:** investigar o comportamento de consultas geradas por frameworks de persistência, comparar estratégias de carregamento de relacionamentos e avaliar o impacto de índices.
3. **Testes de desempenho:** submeter os Web Services a diferentes níveis de carga, utilizando ferramentas apropriadas, para medir e comparar o desempenho das soluções implementadas.

O trabalho deverá privilegiar a **análise experimental**, apresentando evidências quantitativas que permitam avaliar os resultados das otimizações.

**OBS**: O grupo que optar em implementar apenas 2 dos 3 itens a seguir, perderá apenas **1,5** não nota final. Se implementar apenas 1, o trabalho valerá no máximo **5,0** pontos

## 2. Características gerais da aplicação

Cada grupo deverá desenvolver uma aplicação simples, disponibilizada por meio de Web Services, preferencialmente utilizando uma API REST.

**Não será necessário desenvolver uma interface gráfica (frontend).** As funcionalidades poderão ser acessadas diretamente por requisições HTTP, utilizando ferramentas como Postman, Insomnia, curl ou ferramentas de testes automatizados.

A aplicação deverá:

* Utilizar um banco de dados relacional, como PostgreSQL, MySQL ou outro equivalente.
* Possuir pelo menos três tabelas relacionadas, incluindo relacionamentos entre entidades.
* Disponibilizar endpoints para consultar informações armazenadas no banco.
* Possuir pelo menos uma operação de atualização de dados, necessária para demonstrar o comportamento do cache.
* Permitir implementar diferentes estratégias de recuperação de informações, para fins de comparação de desempenho.
* Conter um conjunto de dados suficientemente grande para permitir a observação de diferenças entre as estratégias implementadas.

### 2.1. Tecnologias

Os alunos poderão selecionar as tecnologias que desejarem utilizar.

Entretanto, para facilitar a implementação da parte de persistência e a comparação entre estratégias de carregamento, recomenda-se a utilização de:

* Java com Spring Boot;
* Jakarta Persistence (JPA) e Hibernate;
* PostgreSQL ou MySQL;
* Redis ou Caffeine para implementação de cache.

Outras tecnologias serão aceitas, desde que permitam demonstrar os conceitos solicitados.

Para a comparação específica entre **EAGER e LAZY**, recomenda-se utilizar um framework ORM que ofereça essas estratégias de carregamento de relacionamentos, como Hibernate/JPA.

### 2.2. Domínio da aplicação

O domínio é de livre escolha dos grupos.

Alguns exemplos são:

* Sistema de pedidos, clientes e itens;
* Sistema de biblioteca, livros e empréstimos;
* Sistema acadêmico, alunos, disciplinas e matrículas;
* Sistema de vendas, produtos e categorias;
* Sistema de reservas, clientes e serviços.

**Recomendação:** selecionar um domínio simples, priorizando os aspectos relacionados à persistência e ao desempenho, em vez da complexidade das regras de negócio.

### 2.3. Volume de dados

Para tornar os experimentos relevantes, a aplicação deverá conter uma quantidade significativa de registros.

Como referência, recomenda-se:

* Uma entidade principal com pelo menos 10.000 registros;
* Relacionamentos que envolvam outros registros e tabelas;
* Dados variados o suficiente para exercitar filtros, ordenações e diferentes consultas.

Não é necessário cadastrar os registros manualmente. Os grupos poderão utilizar scripts SQL, bibliotecas de geração de dados ou mecanismos de inicialização automática do banco.

O volume poderá ser ajustado conforme a capacidade computacional disponível, desde que seja suficiente para demonstrar os fenômenos estudados.

# ITEM 1 — UTILIZAÇÃO DE CACHE

## 3. Implementação de cache para redução de acessos ao banco de dados

Nesta etapa, os alunos deverão implementar uma estratégia de cache em um Web Service que consulta informações armazenadas no banco de dados.

O objetivo é verificar como o armazenamento temporário de informações pode reduzir a quantidade de consultas e melhorar o desempenho de operações frequentemente executadas.

### 3.1. Identificação de informações cacheáveis

O grupo deverá selecionar uma operação de consulta cujos dados possam ser armazenados temporariamente.

A escolha deverá considerar:

* Frequência de acesso à informação;
* Frequência com que os dados são modificados (volatilidade);
* Custo de recuperação dos dados no banco;
* Consequências da utilização de informações desatualizadas;
* Necessidade de invalidação ou atualização do cache.

Por exemplo, em um sistema de vendas, informações sobre categorias de produtos podem apresentar baixa volatilidade, enquanto preços e estoques podem sofrer modificações mais frequentes.

O grupo deverá justificar a escolha dos dados que serão mantidos em cache.

### 3.2. Implementação das duas versões

O grupo deverá disponibilizar uma operação que permita executar e comparar:

**Cenário A — Sem cache**

O Web Service consulta o banco de dados sempre que uma requisição é recebida.

Exemplo:

GET /api/produtos/10/sem-cache

**Cenário B — Com cache**

O Web Service verifica inicialmente se a informação solicitada está armazenada em cache.

Caso esteja disponível, retorna a informação sem executar novamente a consulta ao banco.

Caso contrário, consulta o banco e armazena o resultado para reutilização.

Exemplo:

GET /api/produtos/10/com-cache

Os endpoints são apenas sugestões. A comparação também poderá ser realizada por meio de configurações alternativas da mesma operação, desde que seja possível identificar claramente qual estratégia está sendo utilizada.

### 3.3. Tecnologia de cache

O grupo poderá utilizar qualquer mecanismo adequado, por exemplo:

* Redis;
* Caffeine;
* Hazelcast;
* Infinispan;
* Outro mecanismo equivalente.

Deverá explicar brevemente a tecnologia escolhida e justificar sua utilização.

### 3.4. Tempo de vida e invalidação

O grupo deverá configurar uma política de expiração do cache (TTL — Time to Live) e demonstrar seu funcionamento.

Também deverá implementar ou demonstrar uma estratégia para evitar que informações modificadas no banco permaneçam incorretamente disponíveis no cache.

**Experimento obrigatório:**

1. Consultar uma informação e registrar o comportamento do cache.
2. Repetir a consulta e verificar se houve reaproveitamento da informação.
3. Modificar a informação correspondente no banco por meio de uma operação da aplicação.
4. Consultar novamente e observar se a informação retornada está atualizada.
5. Demonstrar o comportamento da política de invalidação ou expiração implementada.

Caso a estratégia permita temporariamente a utilização de dados desatualizados, o grupo deverá explicar esse comportamento e os riscos envolvidos.

### 3.5. Análise de desempenho do cache

O grupo deverá comparar as operações com e sem cache, observando:

* Tempo de resposta;
* Quantidade de acessos ao banco de dados;
* Comportamento em situações de cache hit e cache miss;
* Efeito do TTL;
* Consequências de atualização ou invalidação das informações.

**Questões que deverão ser respondidas:**

1. Em quais situações o cache apresentou maior benefício?
2. Como a volatilidade dos dados influenciou a escolha do TTL?
3. Quais são os riscos de utilizar informações desatualizadas?
4. O cache sempre melhorou o desempenho? Justifique com os resultados observados.

# ITEM 2 — OTIMIZAÇÃO DE CONSULTAS AO BANCO DE DADOS

## 4. Comparação entre estratégias de carregamento EAGER e LAZY

Nesta etapa, os alunos deverão investigar como diferentes estratégias de recuperação de entidades relacionadas podem influenciar a quantidade de consultas realizadas ao banco e o desempenho da aplicação.

O grupo deverá utilizar um relacionamento entre entidades, por exemplo:

* Pedido e Cliente;
* Pedido e Itens;
* Aluno e Matrículas;
* Produto e Categoria.

### 4.1. Implementação com LAZY

O grupo deverá implementar uma operação utilizando carregamento sob demanda (*Lazy Loading*).

Nessa estratégia, entidades ou coleções relacionadas são carregadas quando seus dados são efetivamente necessários.

Exemplo ilustrativo com JPA:

@OneToMany(

mappedBy = "pedido",

fetch = FetchType.LAZY

)

private List<Item> itens;

A implementação deverá permitir observar quando as consultas adicionais são executadas.

O grupo deverá demonstrar um cenário no qual o acesso aos relacionamentos provoque consultas adicionais, como o problema conhecido como **N+1 queries**.

### 4.2. Implementação com EAGER

O grupo deverá implementar uma versão equivalente utilizando carregamento antecipado (*Eager Loading*).

Exemplo:

@OneToMany(

mappedBy = "pedido",

fetch = FetchType.EAGER

)

private List<Item> itens;

O grupo deverá observar e registrar o comportamento do framework, comparando-o com a versão LAZY.

**Importante:** o carregamento EAGER não garante que todas as informações sejam recuperadas por meio de uma única consulta SQL. Dependendo do relacionamento, da consulta e do framework utilizado, poderão ocorrer consultas adicionais.

Portanto, a comparação deverá ser realizada a partir do comportamento efetivamente observado, e não apenas das configurações declaradas no código.

### 4.3. Comparação das estratégias

O grupo deverá executar as operações com diferentes quantidades de registros, registrando:

* Quantidade de consultas SQL executadas;
* Tempo de resposta;
* Volume de informações recuperadas;
* Possíveis efeitos do carregamento de dados desnecessários;
* Ocorrência ou não do problema N+1.

Deverá explicar em quais situações LAZY ou EAGER podem ser mais adequados.

### 4.4. Otimização das consultas

Após investigar as duas estratégias, o grupo deverá implementar pelo menos uma alternativa de otimização.

Exemplos:

* Utilização de JOIN FETCH em JPQL;
* Utilização de consultas nativas SQL;
* Utilização de projeções ou DTOs;
* Recuperação de informações em lote (*batch fetching*);
* Ajustes nas consultas geradas pelo framework.

A solução deverá buscar reduzir consultas desnecessárias ou melhorar a eficiência da recuperação dos dados.

Deverão ser comparados os resultados da implementação original e da versão otimizada.

O grupo também deverá discutir se a utilização de SQL nativo trouxe benefícios reais e quais consequências essa escolha pode apresentar para a manutenção e portabilidade do sistema.

## 5. Utilização de índices para otimização de consultas

Além das estratégias de carregamento, o grupo deverá investigar o impacto dos índices sobre o desempenho de consultas ao banco de dados.

### 5.1. Seleção de uma consulta

O grupo deverá selecionar uma consulta que envolva uma ou mais operações como:

* Filtros por determinados campos;
* Relacionamentos entre tabelas (JOIN);
* Ordenação de registros;
* Busca por intervalos;
* Recuperação de grandes quantidades de registros.

Exemplo:

SELECT *

FROM pedido

WHERE cliente_id = 150

ORDER BY data_pedido DESC;

### 5.2. Comparação sem índice e com índice

O grupo deverá executar a consulta inicialmente sem um índice específico criado para a otimização proposta.

Em seguida, deverá criar um índice adequado e executar novamente a consulta.

Exemplo:

CREATE INDEX idx_pedido_cliente_data

ON pedido (cliente_id, data_pedido DESC);

Deverão ser registrados e comparados os resultados antes e depois da criação do índice.

É importante observar que o banco poderá utilizar outros índices existentes. O grupo deverá identificar esse comportamento no plano de execução.

### 5.3. Análise do plano de execução

O grupo deverá utilizar recursos de análise do banco de dados, como:

* EXPLAIN;
* EXPLAIN ANALYZE;
* Ou mecanismos equivalentes oferecidos pelo banco escolhido.

Deverá apresentar evidências sobre o comportamento das consultas, identificando, quando aplicável:

* Varreduras completas de tabelas (*table scans*);
* Utilização de índices (*index scans*);
* Operações de ordenação;
* Quantidade de registros processados;
* Tempo de execução.

### 5.4. Análise dos resultados

O grupo deverá responder:

1. O índice foi efetivamente utilizado pelo banco?
2. Houve redução no tempo de execução?
3. Quais fatores influenciaram o resultado?
4. Quais podem ser os custos de manter índices adicionais?
5. Criar índices em todas as colunas consultadas seria uma boa estratégia? Por quê?

# ITEM 3 — TESTES DE DESEMPENHO

## 6. Avaliação experimental dos Web Services

Nesta etapa, os grupos deverão executar testes de desempenho sobre os serviços desenvolvidos, utilizando diferentes níveis de carga.

O objetivo será avaliar quantitativamente as técnicas de otimização implementadas nas etapas anteriores.

### 6.1. Escolha da ferramenta

O grupo poderá utilizar qualquer ferramenta apropriada para geração de carga e testes de desempenho.

Exemplos:

* Apache JMeter;
* Grafana k6;
* Gatling;
* Locust;
* Outra ferramenta equivalente.

A ferramenta escolhida deverá ser apresentada brevemente, justificando sua utilização.

### 6.2. Definição dos cenários

O grupo deverá elaborar cenários que permitam comparar as diferentes versões dos Web Services.

**Cenário 1 — Cache**

Comparar o desempenho da consulta sem cache e com cache habilitado.

Deverão ser observadas tanto a utilização do cache já preenchido quanto as situações em que os dados ainda não estão armazenados.

**Cenário 2 — Estratégias de persistência**

Comparar o desempenho das implementações LAZY, EAGER e da estratégia de consulta otimizada.

**Cenário 3 — Índices**

Comparar o desempenho da consulta selecionada antes e depois da criação do índice.

O grupo poderá acrescentar outros cenários, caso considere relevante.

### 6.3. Variação de carga

Cada cenário deverá ser submetido a diferentes níveis de carga.

Como referência, os grupos poderão utilizar:

| **Nível** | **Usuários virtuais simultâneos** |
| --- | --- |
| Baixo | 10 |
| Médio | 50 |
| Alto | 100 |
| Muito alto | 200 |

Esses valores são sugestões e poderão ser adaptados à infraestrutura disponível.

Os testes deverão utilizar duração e volume de requisições suficientes para permitir a comparação dos resultados.

A quantidade de usuários virtuais não deve ser confundida com a quantidade de requisições por segundo, pois cada usuário virtual poderá realizar múltiplas requisições ao longo do teste.

### 6.4. Métricas obrigatórias

Os resultados deverão apresentar, no mínimo:

**a) Latência média**

Tempo médio necessário para responder às requisições.

**b) Latência p95**

Tempo abaixo do qual se encontram aproximadamente 95% das requisições.

**c) Latência p99**

Tempo abaixo do qual se encontram aproximadamente 99% das requisições.

**d) Throughput**

Quantidade de requisições processadas por unidade de tempo, preferencialmente requisições por segundo.

**e) Taxa de erros**

Percentual de requisições que apresentaram falhas.

Sempre que possível, também deverão ser analisados o consumo de CPU, memória e o comportamento do banco de dados.

### 6.5. Cuidados com a execução dos testes

Para garantir comparações consistentes, os testes deverão:

* Utilizar ambientes e configurações equivalentes;
* Empregar as mesmas cargas para comparar as diferentes implementações;
* Registrar a quantidade de dados existente no banco;
* Controlar, quando aplicável, o estado inicial do cache;
* Considerar o aquecimento da aplicação antes da coleta dos resultados;
* Evitar execução simultânea de atividades que possam distorcer as medições;
* Repetir os experimentos para verificar a consistência dos resultados.

Os testes devem ser executados exclusivamente em aplicações e ambientes próprios ou expressamente autorizados, preferencialmente locais ou isolados.

### 6.6. Análise comparativa

O grupo deverá produzir tabelas e gráficos comparando o desempenho das diferentes versões.

Exemplo de apresentação dos resultados (valores fictícios):

| **Implementação** | **Latência média** | **p95** | **Throughput** |
| --- | --- | --- | --- |
| Sem cache | 300 ms | 600 ms | 150 req/s |
| Com cache | 80 ms | 140 ms | 500 req/s |
| Consulta original | 450 ms | 900 ms | 100 req/s |
| Consulta otimizada | 120 ms | 250 ms | 350 req/s |

A tabela acima é apenas ilustrativa. Os grupos deverão apresentar os valores efetivamente obtidos em seus experimentos.

### 6.7. Discussão dos resultados

O grupo deverá analisar criticamente os resultados encontrados, respondendo:

1. Qual técnica apresentou os maiores ganhos de desempenho?
2. Os ganhos foram mantidos quando a carga aumentou?
3. Houve diferenças relevantes entre latência média, p95 e p99?
4. Alguma otimização apresentou resultados inferiores aos esperados?
5. Quais foram os principais gargalos identificados?
6. Como a redução das consultas ao banco influenciou o desempenho?
7. Quais são os possíveis custos ou riscos das otimizações adotadas?

# 7. ENTREGÁVEIS

Os grupos deverão entregar os seguintes materiais.

## 7.1. Código-fonte

Repositório contendo:

* Código dos Web Services;
* Configurações utilizadas;
* Scripts para criação e população do banco;
* Implementações alternativas para os experimentos;
* Scripts ou arquivos utilizados nos testes de desempenho;
* Instruções para executar a aplicação e reproduzir os experimentos.

## 7.2. Relatório técnico em formato [README.MD](http://readme.md) (markdown)

O relatório deverá conter:

**1. Introdução**

Apresentação da aplicação e dos objetivos do trabalho.

**2. Arquitetura e tecnologias**

Descrição dos Web Services, do banco de dados, das entidades e das ferramentas utilizadas.

**3. Implementação de cache**

Descrição da estratégia adotada, tecnologia, TTL, invalidação e resultados comparativos.

**4. Otimização das consultas**

Comparação entre LAZY e EAGER, análise das consultas geradas, solução otimizada e uso de índices.

**5. Testes de desempenho**

Descrição da ferramenta utilizada, cenários, cargas, métricas e resultados.

**6. Discussão**

Análise crítica dos ganhos, limitações, custos e possíveis trade-offs das otimizações.

**7. Conclusão**

Síntese das principais observações e aprendizados.

O relatório deverá incluir gráficos, tabelas, trechos de código e evidências dos experimentos.

## 7.3. Apresentação prática

Cada grupo deverá realizar uma apresentação demonstrando:

* A arquitetura simplificada da aplicação;
* O funcionamento dos Web Services;
* A utilização do cache e seu mecanismo de atualização;
* As diferenças entre LAZY e EAGER;
* O comportamento das consultas antes e depois das otimizações;
* A utilização dos índices;
* A execução de pelo menos um teste de desempenho;
* Os principais resultados e conclusões.

**OBS: Sugiro a gravação de um vídeo de no máximo 7 min apresentando o trabalho.**

Não será necessário desenvolver uma interface gráfica para a apresentação.

A demonstração poderá ser realizada com ferramentas de requisições HTTP, visualizadores de banco de dados e ferramentas de testes de carga.

# 9. CONSIDERAÇÕES FINAIS

Este trabalho pretende demonstrar que a otimização de sistemas depende da combinação entre conhecimento técnico, decisões arquiteturais e avaliação experimental.

O uso de cache, a escolha de estratégias de persistência e a criação de índices podem produzir ganhos significativos, mas também introduzir novos custos e problemas.

Por esse motivo, os alunos deverão procurar responder à seguinte questão:

**Como demonstrar, por meio de evidências, que uma mudança realmente melhorou o desempenho de um sistema?**

A ideia central do trabalho é:

**Identificar o problema → Implementar uma alternativa → Medir o desempenho → Comparar os resultados → Justificar as conclusões.**
