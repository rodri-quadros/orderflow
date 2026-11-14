-- Índice só na FK, usado apenas para comparação com o composto (não fica no banco). Executar como admin.
-- Mostra que filtrar por cliente_id não basta: sem data_pedido no índice, o ORDER BY ainda exige Sort.
CREATE INDEX IF NOT EXISTS idx_pedido_cliente ON pedido (cliente_id);
ANALYZE pedido;
