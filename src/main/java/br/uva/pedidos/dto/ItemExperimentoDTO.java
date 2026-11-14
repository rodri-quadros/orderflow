package br.uva.pedidos.dto;

import java.math.BigDecimal;

import br.uva.pedidos.entity.ItemPedido;

public record ItemExperimentoDTO(
    Long produtoId,
    int quantidade,
    BigDecimal precoUnitario
) {

    // getProduto().getId() lê o id do proxy LAZY sem carregar o produto.
    public static ItemExperimentoDTO de(ItemPedido item) {
        return new ItemExperimentoDTO(item.getProduto().getId(), item.getQuantidade(), item.getPrecoUnitario());
    }
}
