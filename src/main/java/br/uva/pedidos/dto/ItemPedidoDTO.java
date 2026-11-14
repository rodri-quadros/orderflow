package br.uva.pedidos.dto;

import java.math.BigDecimal;

import br.uva.pedidos.entity.ItemPedido;

public record ItemPedidoDTO(
    Long id,
    Long produtoId,
    String nomeProduto,
    int quantidade,
    BigDecimal precoUnitario,
    BigDecimal subtotal
) {

    public static ItemPedidoDTO de(ItemPedido item) {
        return new ItemPedidoDTO(item.getId(), item.getProduto().getId(), item.getProduto().getNome(),
            item.getQuantidade(), item.getPrecoUnitario(), item.getSubtotal());
    }
}
