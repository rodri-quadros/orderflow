-- Volta ao estado "sem índice" (estado reproduzível da base). Executar como admin.
DROP INDEX IF EXISTS idx_pedido_cliente_data;
ANALYZE pedido;
