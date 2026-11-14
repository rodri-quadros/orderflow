package br.uva.pedidos.entity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

import br.uva.pedidos.exception.ConflitoException;

class PedidoTest {

    private final Cliente cliente = new Cliente("Cliente Teste", "teste@exemplo.com", null, LocalDateTime.now());

    private static ItemPedido item(String preco, int quantidade) {
        return new ItemPedido(new Produto("Produto", null, new BigDecimal(preco)), quantidade, new BigDecimal(preco));
    }

    @Test
    void deveComecarPendenteESemValor() {
        Pedido pedido = new Pedido(cliente, LocalDateTime.now());

        assertThat(pedido.getStatus()).isEqualTo(StatusPedido.PENDENTE);
        assertThat(pedido.getValorTotal()).isEqualByComparingTo("0");
        assertThat(pedido.getItens()).isEmpty();
    }

    @Test
    void deveDefinirAReferenciaInversaAoAdicionarItem() {
        Pedido pedido = new Pedido(cliente, LocalDateTime.now());
        ItemPedido item = item("10.00", 1);

        pedido.adicionarItem(item);

        assertThat(item.getPedido()).isSameAs(pedido);
        assertThat(pedido.getItens()).containsExactly(item);
    }

    @Test
    void deveCalcularValorTotalComoSomaDeQuantidadeVezesPrecoUnitario() {
        Pedido pedido = new Pedido(cliente, LocalDateTime.now());

        pedido.adicionarItem(item("19.99", 3));     // 59.97
        pedido.adicionarItem(item("0.05", 2));      //  0.10
        pedido.adicionarItem(item("1419.87", 1));   // 1419.87

        // Preços com 2 casas (garantido por @Digits e NUMERIC(10,2)) vezes inteiro: resultado exato com
        // 2 casas, igual ao que NUMERIC(12,2) armazena, sem arredondamento.
        assertThat(pedido.getValorTotal()).isEqualByComparingTo("1479.94");
        assertThat(pedido.getValorTotal().scale()).isEqualTo(2);
    }

    @ParameterizedTest
    @EnumSource(value = StatusPedido.class, names = {"APROVADO", "CANCELADO"})
    void deveAprovarOuCancelarPedidoPendente(StatusPedido novo) {
        Pedido pedido = new Pedido(cliente, LocalDateTime.now());

        pedido.alterarStatus(novo);

        assertThat(pedido.getStatus()).isEqualTo(novo);
    }

    @ParameterizedTest
    @EnumSource(StatusPedido.class)
    void deveLancarConflitoAoAlterarPedidoJaAprovado(StatusPedido novo) {
        Pedido pedido = new Pedido(cliente, LocalDateTime.now());
        pedido.alterarStatus(StatusPedido.APROVADO);

        assertThatThrownBy(() -> pedido.alterarStatus(novo)).isInstanceOf(ConflitoException.class);
        assertThat(pedido.getStatus()).isEqualTo(StatusPedido.APROVADO);
    }

    @Test
    void deveLancarConflitoAoManterPedidoPendente() {
        Pedido pedido = new Pedido(cliente, LocalDateTime.now());

        assertThatThrownBy(() -> pedido.alterarStatus(StatusPedido.PENDENTE)).isInstanceOf(ConflitoException.class);
    }
}
