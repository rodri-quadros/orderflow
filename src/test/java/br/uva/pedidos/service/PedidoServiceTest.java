package br.uva.pedidos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import br.uva.pedidos.dto.ItemPedidoDTO;
import br.uva.pedidos.dto.ItemPedidoRequest;
import br.uva.pedidos.dto.PedidoDTO;
import br.uva.pedidos.dto.PedidoRequest;
import br.uva.pedidos.entity.Cliente;
import br.uva.pedidos.entity.Pedido;
import br.uva.pedidos.entity.Produto;
import br.uva.pedidos.exception.RecursoNaoEncontradoException;
import br.uva.pedidos.exception.RegraNegocioException;
import br.uva.pedidos.repository.ClienteRepository;
import br.uva.pedidos.repository.PedidoRepository;
import br.uva.pedidos.repository.ProdutoRepository;

@ExtendWith(MockitoExtension.class)
class PedidoServiceTest {

    private static final long CLIENTE = 1L;

    @Mock
    private PedidoRepository pedidoRepository;
    @Mock
    private ClienteRepository clienteRepository;
    @Mock
    private ProdutoRepository produtoRepository;
    @InjectMocks
    private PedidoService pedidoService;

    // O id é gerado pelo banco; nos testes sem banco ele é definido por reflexão.
    private static Produto produto(long id, String preco, boolean ativo) {
        Produto produto = new Produto("Produto " + id, null, new BigDecimal(preco));
        produto.setAtivo(ativo);
        ReflectionTestUtils.setField(produto, "id", id);
        return produto;
    }

    private static PedidoRequest pedido(ItemPedidoRequest... itens) {
        return new PedidoRequest(CLIENTE, List.of(itens));
    }

    private void dadoClienteExistente() {
        when(clienteRepository.findById(CLIENTE))
            .thenReturn(Optional.of(new Cliente("Cliente 1", "c1@exemplo.com", null, LocalDateTime.now())));
    }

    @Test
    void deveLancarNaoEncontradoQuandoClienteNaoExiste() {
        when(clienteRepository.findById(CLIENTE)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> pedidoService.criar(pedido(new ItemPedidoRequest(10L, 1))))
            .isInstanceOf(RecursoNaoEncontradoException.class);
        verify(produtoRepository, never()).findAllById(any());
    }

    @Test
    void deveLancarNaoEncontradoQuandoProdutoNaoExiste() {
        dadoClienteExistente();
        when(produtoRepository.findAllById(any())).thenReturn(List.of());

        assertThatThrownBy(() -> pedidoService.criar(pedido(new ItemPedidoRequest(99L, 1))))
            .isInstanceOf(RecursoNaoEncontradoException.class)
            .hasMessageContaining("99");
    }

    @Test
    void deveLancarRegraNegocioQuandoProdutoEstaInativo() {
        dadoClienteExistente();
        when(produtoRepository.findAllById(any())).thenReturn(List.of(produto(5L, "10.00", false)));

        assertThatThrownBy(() -> pedidoService.criar(pedido(new ItemPedidoRequest(5L, 1))))
            .isInstanceOf(RegraNegocioException.class)
            .hasMessageContaining("inativo");
        verify(pedidoRepository, never()).save(any());
    }

    @Test
    void deveLancarRegraNegocioQuandoProdutoSeRepete() {
        dadoClienteExistente();

        assertThatThrownBy(() -> pedidoService.criar(pedido(new ItemPedidoRequest(10L, 1), new ItemPedidoRequest(10L, 2))))
            .isInstanceOf(RegraNegocioException.class);
        verify(produtoRepository, never()).findAllById(any());
    }

    @Test
    void deveCopiarPrecoDoProdutoECarregarTodosOsProdutosEmUmaUnicaConsulta() {
        dadoClienteExistente();
        when(produtoRepository.findAllById(any()))
            .thenReturn(List.of(produto(10L, "1419.87", true), produto(20L, "1236.44", true), produto(40L, "33.43", true)));
        when(pedidoRepository.save(any(Pedido.class))).thenAnswer(invocacao -> invocacao.getArgument(0));

        PedidoDTO pedido = pedidoService.criar(pedido(
            new ItemPedidoRequest(10L, 2), new ItemPedidoRequest(20L, 1), new ItemPedidoRequest(40L, 3)));

        assertThat(pedido.itens()).extracting(ItemPedidoDTO::precoUnitario)
            .containsExactly(new BigDecimal("1419.87"), new BigDecimal("1236.44"), new BigDecimal("33.43"));
        assertThat(pedido.valorTotal()).isEqualByComparingTo("4176.47");
        // Uma única ida ao banco para os 3 produtos (sem N+1 na criação) e nenhuma busca produto a produto.
        verify(produtoRepository, times(1)).findAllById(any());
        verifyNoMoreInteractions(produtoRepository);
    }
}
