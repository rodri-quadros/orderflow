package br.uva.pedidos.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import br.uva.pedidos.entity.Pedido;
import br.uva.pedidos.entity.StatusPedido;

public record PedidoDTO(
    Long id,
    LocalDateTime dataPedido,
    StatusPedido status,
    BigDecimal valorTotal,
    ClienteDTO cliente,
    List<ItemPedidoDTO> itens
) {

    // Acessa cliente e itens (LAZY): chamar dentro da transação, com eles já carregados.
    public static PedidoDTO de(Pedido pedido) {
        return new PedidoDTO(pedido.getId(), pedido.getDataPedido(), pedido.getStatus(),
            pedido.getValorTotal(), ClienteDTO.de(pedido.getCliente()),
            pedido.getItens().stream().map(ItemPedidoDTO::de).toList());
    }
}
