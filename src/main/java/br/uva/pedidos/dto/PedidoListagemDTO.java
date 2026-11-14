package br.uva.pedidos.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import br.uva.pedidos.entity.Pedido;
import br.uva.pedidos.entity.PedidoEager;

// Linha de um grid de pedidos (pedido, cliente, valor), sem itens, como na reflexão da aula.
public record PedidoListagemDTO(
    Long id,
    LocalDateTime dataPedido,
    String clienteNome,
    BigDecimal valorTotal
) {

    public static PedidoListagemDTO de(Pedido pedido) {
        return new PedidoListagemDTO(pedido.getId(), pedido.getDataPedido(),
            pedido.getCliente().getNome(), pedido.getValorTotal());
    }

    public static PedidoListagemDTO de(PedidoEager pedido) {
        return new PedidoListagemDTO(pedido.getId(), pedido.getDataPedido(),
            pedido.getCliente().getNome(), pedido.getValorTotal());
    }
}
