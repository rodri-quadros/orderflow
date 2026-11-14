-- Planos da consulta "pedidos de um cliente ordenados pela data" (enunciado 5.1; slide de índices).
-- Uso manual (como admin ou pedidos_app):
--   psql -h 127.0.0.1 -p $POSTGRES_PORT -U <usuario> -d $POSTGRES_DB -v cliente=1 -f db/indice/explain_pedidos_cliente.sql
-- scripts/experimento-indice.sh separa os blocos pelos marcadores "-- consulta:".
--
-- A: SQL gerado pelo Hibernate para GET /api/clientes/{id}/pedidos, copiado do log (SQL_LOG_LEVEL=debug).
--    Os parâmetros ligados foram substituídos pelos valores do log: cliente_id, offset 40 (page=2) e 20 (size).

-- consulta: A_pagina0
EXPLAIN (ANALYZE, BUFFERS)
    select
        p1_0.id,
        p1_0.data_pedido,
        p1_0.status,
        p1_0.valor_total 
    from
        pedido p1_0 
    where
        p1_0.cliente_id=:cliente 
    order by
        p1_0.data_pedido desc 
    fetch
        first 20 rows only;

-- consulta: A_pagina2
EXPLAIN (ANALYZE, BUFFERS)
    select
        p1_0.id,
        p1_0.data_pedido,
        p1_0.status,
        p1_0.valor_total 
    from
        pedido p1_0 
    where
        p1_0.cliente_id=:cliente 
    order by
        p1_0.data_pedido desc 
    offset
        40 rows 
    fetch
        first 20 rows only;

-- consulta: B_sem_limite
-- Consulta do enunciado (5.1), sem limite.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedido
WHERE cliente_id = :cliente
ORDER BY data_pedido DESC;

-- consulta: C_intervalo
-- Consulta do slide de índices, com intervalo de datas.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedido
WHERE cliente_id = :cliente
  AND data_pedido >= '2026-01-01'
ORDER BY data_pedido DESC;
