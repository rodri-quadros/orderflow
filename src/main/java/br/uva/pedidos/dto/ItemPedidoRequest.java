package br.uva.pedidos.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

// Sem preço: o preço unitário é sempre copiado do produto pelo servidor.
public record ItemPedidoRequest(
    @NotNull @Positive Long produtoId,
    @NotNull @Positive @Max(1000) Integer quantidade
) {
}
