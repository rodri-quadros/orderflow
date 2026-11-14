package br.uva.pedidos.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import br.uva.pedidos.entity.StatusPedido;

public record PedidoResumoDTO(
    Long id,
    LocalDateTime dataPedido,
    StatusPedido status,
    BigDecimal valorTotal
) {
}
