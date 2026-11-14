package br.uva.pedidos.dto;

import jakarta.validation.constraints.NotNull;

import br.uva.pedidos.entity.StatusPedido;

public record AlterarStatusRequest(@NotNull StatusPedido status) {
}
