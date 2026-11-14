-- Verificação do volume e da integridade dos dados (executar sob demanda, pelo host):
--   set -a; . ./.env; set +a
--   PGPASSWORD=$APP_DB_PASSWORD psql -h 127.0.0.1 -p $POSTGRES_PORT -U $APP_DB_USER -d $POSTGRES_DB \
--     -f db/validacao_dados.sql > resultados/volume-dados.txt

\echo '== Contagem por tabela'
SELECT 'cliente' AS tabela, count(*) AS linhas FROM cliente
UNION ALL SELECT 'produto', count(*) FROM produto
UNION ALL SELECT 'produto (ativos)', count(*) FROM produto WHERE ativo
UNION ALL SELECT 'pedido', count(*) FROM pedido
UNION ALL SELECT 'item_pedido', count(*) FROM item_pedido;

\echo '== Itens por pedido'
SELECT min(qtd) AS minimo, round(avg(qtd), 2) AS media, max(qtd) AS maximo
FROM (SELECT count(*) AS qtd FROM item_pedido GROUP BY pedido_id) t;

\echo '== Pedidos por cliente (inclui clientes sem pedido)'
SELECT min(qtd) AS minimo, round(avg(qtd), 2) AS media,
       percentile_disc(0.5) WITHIN GROUP (ORDER BY qtd) AS mediana, max(qtd) AS maximo
FROM (SELECT count(p.id) AS qtd FROM cliente c LEFT JOIN pedido p ON p.cliente_id = c.id GROUP BY c.id) t;

\echo '== Clientes por faixa de quantidade de pedidos'
SELECT CASE WHEN qtd = 0 THEN '0'
            WHEN qtd <= 5 THEN '1-5'
            WHEN qtd <= 10 THEN '6-10'
            WHEN qtd <= 20 THEN '11-20'
            WHEN qtd <= 50 THEN '21-50'
            ELSE '51+' END AS faixa,
       count(*) AS clientes
FROM (SELECT count(p.id) AS qtd FROM cliente c LEFT JOIN pedido p ON p.cliente_id = c.id GROUP BY c.id) t
GROUP BY 1
ORDER BY min(qtd);

\echo '== 5 clientes com mais pedidos (candidatos para o experimento de índices)'
SELECT cliente_id, count(*) AS pedidos
FROM pedido
GROUP BY cliente_id
ORDER BY pedidos DESC, cliente_id
LIMIT 5;

\echo '== Cliente típico (quantidade de pedidos igual à mediana)'
WITH contagem AS (
    SELECT c.id AS cliente_id, count(p.id) AS pedidos
    FROM cliente c LEFT JOIN pedido p ON p.cliente_id = c.id
    GROUP BY c.id
)
SELECT cliente_id, pedidos
FROM contagem
WHERE pedidos = (SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY pedidos) FROM contagem)
ORDER BY cliente_id
LIMIT 1;

\echo '== Integridade (todas as colunas devem ser 0)'
SELECT
    (SELECT count(*) FROM pedido p
      WHERE NOT EXISTS (SELECT 1 FROM item_pedido i WHERE i.pedido_id = p.id)) AS pedidos_sem_itens,
    (SELECT count(*) FROM item_pedido i
      WHERE NOT EXISTS (SELECT 1 FROM pedido p WHERE p.id = i.pedido_id)) AS itens_orfaos,
    (SELECT count(*) FROM item_pedido i JOIN produto pr ON pr.id = i.produto_id
      WHERE NOT pr.ativo) AS itens_produto_inativo,
    (SELECT count(*) FROM pedido p
       JOIN (SELECT pedido_id, sum(quantidade * preco_unitario) AS soma
             FROM item_pedido GROUP BY pedido_id) s ON s.pedido_id = p.id
      WHERE p.valor_total <> s.soma) AS total_divergente;

\echo '== Distribuição de status'
SELECT status, count(*) AS pedidos,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS percentual
FROM pedido
GROUP BY status
ORDER BY pedidos DESC;

\echo '== Checksum de reprodutibilidade'
SELECT count(*) AS pedidos, sum(valor_total) AS soma_valor_total,
       sum(cliente_id) AS soma_cliente_id, min(data_pedido) AS primeiro, max(data_pedido) AS ultimo
FROM pedido;

\echo '== Tamanho das tabelas'
SELECT relname AS tabela,
       pg_size_pretty(pg_table_size(relid)) AS dados,
       pg_size_pretty(pg_indexes_size(relid)) AS indices,
       pg_size_pretty(pg_total_relation_size(relid)) AS total
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

\echo '== Índices existentes'
SELECT i.tablename AS tabela, i.indexname AS indice,
       pg_size_pretty(pg_relation_size(format('%I.%I', i.schemaname, i.indexname)::regclass)) AS tamanho,
       i.indexdef AS definicao
FROM pg_indexes i
WHERE i.schemaname = 'public'
ORDER BY i.tablename, i.indexname;
