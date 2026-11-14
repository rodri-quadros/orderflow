package br.uva.pedidos.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Comparator;
import java.util.List;

import br.uva.pedidos.entity.ItemPedido;
import br.uva.pedidos.entity.Pedido;
import br.uva.pedidos.entity.PedidoEager;
import br.uva.pedidos.entity.StatusPedido;

// Resultado comum a todas as estratégias, para que o JSON de cada uma possa ser comparado.
public record PedidoExperimentoDTO(
    Long id,
    LocalDateTime dataPedido,
    StatusPedido status,
    BigDecimal valorTotal,
    String clienteNome,
    List<ItemExperimentoDTO> itens
) {

    public static PedidoExperimentoDTO de(Pedido pedido) {
        return new PedidoExperimentoDTO(pedido.getId(), pedido.getDataPedido(), pedido.getStatus(),
            pedido.getValorTotal(), pedido.getCliente().getNome(), itens(pedido.getItens()));
    }

    public static PedidoExperimentoDTO de(PedidoEager pedido) {
        return new PedidoExperimentoDTO(pedido.getId(), pedido.getDataPedido(), pedido.getStatus(),
            pedido.getValorTotal(), pedido.getCliente().getNome(), itens(pedido.getItens()));
    }

    // Ordena por id do item: a ordem de uma coleção carregada do banco não é garantida.
    private static List<ItemExperimentoDTO> itens(List<ItemPedido> itens) {
        return itens.stream()
            .sorted(Comparator.comparing(ItemPedido::getId))
            .map(ItemExperimentoDTO::de)
            .toList();
    }
}
