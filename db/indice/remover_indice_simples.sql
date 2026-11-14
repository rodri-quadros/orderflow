-- Remove o índice de comparação. Executar como admin.
DROP INDEX IF EXISTS idx_pedido_cliente;
ANALYZE pedido;
