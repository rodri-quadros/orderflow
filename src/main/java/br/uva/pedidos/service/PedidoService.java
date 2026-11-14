package br.uva.pedidos.service;

import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import br.uva.pedidos.dto.ItemPedidoRequest;
import br.uva.pedidos.dto.PedidoDTO;
import br.uva.pedidos.dto.PedidoRequest;
import br.uva.pedidos.entity.Cliente;
import br.uva.pedidos.entity.ItemPedido;
import br.uva.pedidos.entity.Pedido;
import br.uva.pedidos.entity.Produto;
import br.uva.pedidos.entity.StatusPedido;
import br.uva.pedidos.exception.RecursoNaoEncontradoException;
import br.uva.pedidos.exception.RegraNegocioException;
import br.uva.pedidos.repository.ClienteRepository;
import br.uva.pedidos.repository.PedidoRepository;
import br.uva.pedidos.repository.ProdutoRepository;

@Service
public class PedidoService {

    private final PedidoRepository pedidoRepository;
    private final ClienteRepository clienteRepository;
    private final ProdutoRepository produtoRepository;

    public PedidoService(PedidoRepository pedidoRepository, ClienteRepository clienteRepository,
                         ProdutoRepository produtoRepository) {
        this.pedidoRepository = pedidoRepository;
        this.clienteRepository = clienteRepository;
        this.produtoRepository = produtoRepository;
    }

    @Transactional
    public PedidoDTO criar(PedidoRequest request) {
        Cliente cliente = clienteRepository.findById(request.clienteId())
            .orElseThrow(() -> new RecursoNaoEncontradoException("Cliente " + request.clienteId() + " não encontrado"));
        Map<Long, Produto> produtos = carregarProdutos(request.itens());

        Pedido pedido = new Pedido(cliente, LocalDateTime.now());
        for (ItemPedidoRequest item : request.itens()) {
            Produto produto = produtos.get(item.produtoId());
            pedido.adicionarItem(new ItemPedido(produto, item.quantidade(), produto.getPreco()));
        }
        return PedidoDTO.de(pedidoRepository.save(pedido));
    }

    @Transactional(readOnly = true)
    public PedidoDTO buscar(Long id) {
        return PedidoDTO.de(buscarComItens(id));
    }

    @Transactional
    public PedidoDTO alterarStatus(Long id, StatusPedido novoStatus) {
        Pedido pedido = buscarComItens(id);
        pedido.alterarStatus(novoStatus);
        return PedidoDTO.de(pedido);
    }

    private Pedido buscarComItens(Long id) {
        return pedidoRepository.buscarComItens(id)
            .orElseThrow(() -> new RecursoNaoEncontradoException("Pedido " + id + " não encontrado"));
    }

    // Uma consulta para todos os produtos do pedido, em vez de uma por item (evita 1 + N).
    // Lê sempre do banco, nunca do cache: o preço cobrado não pode vir de um valor desatualizado.
    private Map<Long, Produto> carregarProdutos(List<ItemPedidoRequest> itens) {
        List<Long> ids = itens.stream().map(ItemPedidoRequest::produtoId).toList();
        Set<Long> idsUnicos = new HashSet<>(ids);
        if (idsUnicos.size() < ids.size()) {
            throw new RegraNegocioException("O mesmo produto não pode aparecer mais de uma vez no pedido");
        }

        Map<Long, Produto> produtos = produtoRepository.findAllById(idsUnicos).stream()
            .collect(Collectors.toMap(Produto::getId, Function.identity()));
        for (Long id : ids) {
            Produto produto = produtos.get(id);
            if (produto == null) {
                throw new RecursoNaoEncontradoException("Produto " + id + " não encontrado");
            }
            if (!produto.isAtivo()) {
                throw new RegraNegocioException("Produto " + id + " está inativo");
            }
        }
        return produtos;
    }
}
