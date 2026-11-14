package br.uva.pedidos.dto;

import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record PedidoRequest(
    @NotNull @Positive Long clienteId,
    @NotEmpty List<@Valid @NotNull ItemPedidoRequest> itens
) {
}
