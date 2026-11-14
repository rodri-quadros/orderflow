-- Índice composto do experimento (aula e enunciado, seção 5.2). Executar como admin:
--   PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -h 127.0.0.1 -p $POSTGRES_PORT -U $POSTGRES_ADMIN_USER -d $POSTGRES_DB -f db/indice/criar_indice.sql
-- cliente_id primeiro (filtro de igualdade) e data_pedido DESC em seguida: a ordem do índice já
-- atende o ORDER BY data_pedido DESC, sem nó Sort, e permite parar após o LIMIT.
CREATE INDEX IF NOT EXISTS idx_pedido_cliente_data ON pedido (cliente_id, data_pedido DESC);
ANALYZE pedido;
