-- População reproduzível: mesma semente => mesmos dados.
-- Executado como admin após 02_schema.sql. Ajuste os volumes abaixo.
\set qtd_clientes 10000
\set qtd_produtos 1000
\set qtd_pedidos 100000
-- Data fixa em vez de now(): com now() as datas mudariam a cada recarga e os
-- resultados das consultas por período deixariam de ser comparáveis.
\set data_ref '2026-11-01 00:00:00'

-- random() é determinístico após setseed() desde que seja chamado sempre na mesma
-- ordem; por isso os sorteios são feitos em tabelas temporárias com ORDER BY e os
-- ids são atribuídos explicitamente.
SELECT setseed(0.42);

INSERT INTO cliente (id, nome, email, telefone, data_cadastro)
SELECT g,
       'Cliente ' || g,
       'cliente' || g || '@exemplo.com',
       '(21) 9' || lpad(floor(random() * 100000000)::bigint::text, 8, '0'),
       date_trunc('second', :'data_ref'::timestamp - random() * interval '1095 days')
FROM generate_series(1, :qtd_clientes) g;

INSERT INTO produto (id, nome, descricao, preco, ativo)
SELECT g,
       'Produto ' || g,
       'Descrição do produto ' || g || ' para testes de desempenho',
       round((5 + random() * 1995)::numeric, 2),
       random() >= 0.10
FROM generate_series(1, :qtd_produtos) g;

-- Sorteios por pedido. power(random(), 1.5) concentra pedidos nos ids menores:
-- alguns clientes ficam com centenas de pedidos e a maioria com poucos.
CREATE TEMP TABLE tmp_pedido AS
SELECT g AS num,
       1 + floor(power(random(), 1.5) * :qtd_clientes)::bigint AS cliente_id,
       date_trunc('second', :'data_ref'::timestamp - random() * interval '730 days') AS data_pedido,
       random() AS sorteio_status,
       1 + floor(random() * 5)::int AS qtd_itens
FROM generate_series(1, :qtd_pedidos) g;

CREATE TEMP TABLE tmp_ativo AS
SELECT row_number() OVER (ORDER BY id) AS posicao, id, preco
FROM produto
WHERE ativo;

SELECT count(*) AS qtd_ativos FROM tmp_ativo \gset

CREATE TEMP TABLE tmp_sorteio_item AS
SELECT p.num AS pedido_num,
       i AS item_num,
       1 + floor(random() * :qtd_ativos)::int AS posicao,
       1 + floor(random() * 10)::int AS quantidade,
       0.85 + random() * 0.15 AS fator_preco
FROM tmp_pedido p, generate_series(1, p.qtd_itens) i
ORDER BY p.num, i;

-- preco_unitario difere do preço atual: simula o preço praticado na época do pedido.
CREATE TEMP TABLE tmp_item AS
SELECT s.pedido_num, s.item_num, a.id AS produto_id, s.quantidade,
       round(a.preco * s.fator_preco::numeric, 2) AS preco_unitario
FROM tmp_sorteio_item s
JOIN tmp_ativo a ON a.posicao = s.posicao;

-- Os itens são montados antes dos pedidos para que valor_total já entre correto
-- (CHECK valor_total > 0). Assim evitamos inserir um valor provisório e depois
-- dar UPDATE em 100 mil linhas, o que deixaria versões mortas e incharia a tabela
-- usada no experimento de índices.
INSERT INTO pedido (id, cliente_id, data_pedido, status, valor_total)
SELECT p.num,
       p.cliente_id,
       p.data_pedido,
       CASE WHEN p.sorteio_status < 0.60 THEN 'APROVADO'
            WHEN p.sorteio_status < 0.85 THEN 'PENDENTE'
            ELSE 'CANCELADO' END,
       t.total
FROM tmp_pedido p
JOIN (SELECT pedido_num, sum(quantidade * preco_unitario) AS total
      FROM tmp_item
      GROUP BY pedido_num) t ON t.pedido_num = p.num
ORDER BY p.num;

INSERT INTO item_pedido (pedido_id, produto_id, quantidade, preco_unitario)
SELECT pedido_num, produto_id, quantidade, preco_unitario
FROM tmp_item
ORDER BY pedido_num, item_num;

-- Ids explícitos não avançam a identity; sem isto o próximo INSERT da API colidiria.
SELECT setval(pg_get_serial_sequence('cliente', 'id'), (SELECT max(id) FROM cliente));
SELECT setval(pg_get_serial_sequence('produto', 'id'), (SELECT max(id) FROM produto));
SELECT setval(pg_get_serial_sequence('pedido', 'id'), (SELECT max(id) FROM pedido));

DROP TABLE tmp_item, tmp_sorteio_item, tmp_ativo, tmp_pedido;

-- VACUUM além do ANALYZE: atualiza o visibility map já na carga, para que os
-- planos (ex.: index-only scan) não dependam de quando o autovacuum passar.
VACUUM ANALYZE cliente;
VACUUM ANALYZE produto;
VACUUM ANALYZE pedido;
VACUUM ANALYZE item_pedido;
