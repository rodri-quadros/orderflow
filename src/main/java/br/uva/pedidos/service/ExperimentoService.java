package br.uva.pedidos.service;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.persistence.EntityManager;

import org.hibernate.query.NativeQuery;
import org.springframework.data.domain.Limit;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import br.uva.pedidos.dto.ItemExperimentoDTO;
import br.uva.pedidos.dto.PedidoExperimentoDTO;
import br.uva.pedidos.dto.PedidoListagemDTO;
import br.uva.pedidos.entity.Pedido;
import br.uva.pedidos.entity.StatusPedido;
import br.uva.pedidos.exception.RecursoNaoEncontradoException;
import br.uva.pedidos.repository.PedidoEagerRepository;

// Estratégias de carregamento comparadas no experimento (seção 4 do enunciado). Todas devolvem os
// mesmos "limite" primeiros pedidos por id. O mapeamento para DTO acontece dentro da transação
// porque open-in-view está desligado.
@Service
@Transactional(readOnly = true)
public class ExperimentoService {

    private static final String SQL_NATIVA = """
        SELECT p.id, p.data_pedido, p.status, p.valor_total, c.nome AS cliente_nome,
               i.produto_id, i.quantidade, i.preco_unitario
        FROM (SELECT * FROM pedido ORDER BY id LIMIT :limite) p
        JOIN cliente c ON c.id = p.cliente_id
        JOIN item_pedido i ON i.pedido_id = p.id
        ORDER BY p.id, i.id
        """;

    private final EntityManager entityManager;
    private final PedidoEagerRepository pedidoEagerRepository;

    public ExperimentoService(EntityManager entityManager, PedidoEagerRepository pedidoEagerRepository) {
        this.entityManager = entityManager;
        this.pedidoEagerRepository = pedidoEagerRepository;
    }

    // 1 consulta para os pedidos; cada getCliente()/getItens() no mapeamento dispara outra (N+1).
    public List<PedidoExperimentoDTO> lazy(int limite) {
        return buscarPedidos(limite).stream().map(PedidoExperimentoDTO::de).toList();
    }

    public List<PedidoExperimentoDTO> eager(int limite) {
        return pedidoEagerRepository.findAllByOrderByIdAsc(Limit.of(limite)).stream()
            .map(PedidoExperimentoDTO::de)
            .toList();
    }

    public PedidoExperimentoDTO eagerPorId(Long id) {
        return pedidoEagerRepository.findById(id)
            .map(PedidoExperimentoDTO::de)
            .orElseThrow(() -> new RecursoNaoEncontradoException("Pedido " + id + " não encontrado"));
    }

    // Dois passos: JOIN FETCH de coleção com limite faria o Hibernate trazer todas as linhas e
    // paginar em memória (aviso HHH90003004). Primeiro os ids, depois o JOIN FETCH só desses pedidos.
    public List<PedidoExperimentoDTO> joinFetch(int limite) {
        List<Long> ids = entityManager.createQuery("SELECT p.id FROM Pedido p ORDER BY p.id", Long.class)
            .setMaxResults(limite)
            .getResultList();
        return entityManager.createQuery("""
                SELECT p FROM Pedido p
                JOIN FETCH p.cliente
                JOIN FETCH p.itens
                WHERE p.id IN :ids
                ORDER BY p.id
                """, Pedido.class)
            .setParameter("ids", ids)
            .getResultList().stream()
            .map(PedidoExperimentoDTO::de)
            .toList();
    }

    // Uma consulta; o limite vai na subconsulta para valer sobre pedidos, não sobre linhas de item.
    @SuppressWarnings("unchecked")
    public List<PedidoExperimentoDTO> nativa(int limite) {
        List<Object[]> linhas = entityManager.createNativeQuery(SQL_NATIVA)
            .unwrap(NativeQuery.class)
            .addScalar("id", Long.class)
            .addScalar("data_pedido", LocalDateTime.class)
            .addScalar("status", String.class)
            .addScalar("valor_total", BigDecimal.class)
            .addScalar("cliente_nome", String.class)
            .addScalar("produto_id", Long.class)
            .addScalar("quantidade", Integer.class)
            .addScalar("preco_unitario", BigDecimal.class)
            .setParameter("limite", limite)
            .getResultList();

        Map<Long, PedidoExperimentoDTO> pedidos = new LinkedHashMap<>();
        for (Object[] linha : linhas) {
            PedidoExperimentoDTO pedido = pedidos.computeIfAbsent((Long) linha[0], id -> new PedidoExperimentoDTO(
                id, (LocalDateTime) linha[1], StatusPedido.valueOf((String) linha[2]),
                (BigDecimal) linha[3], (String) linha[4], new ArrayList<>()));
            pedido.itens().add(new ItemExperimentoDTO((Long) linha[5], (Integer) linha[6], (BigDecimal) linha[7]));
        }
        return new ArrayList<>(pedidos.values());
    }

    // Grid sem itens: com LAZY a coleção nunca é carregada; só os clientes são buscados.
    public List<PedidoListagemDTO> resumoLazy(int limite) {
        return buscarPedidos(limite).stream().map(PedidoListagemDTO::de).toList();
    }

    // Mesmo grid com EAGER: os itens são carregados mesmo sem serem usados.
    public List<PedidoListagemDTO> resumoEager(int limite) {
        return pedidoEagerRepository.findAllByOrderByIdAsc(Limit.of(limite)).stream()
            .map(PedidoListagemDTO::de)
            .toList();
    }

    private List<Pedido> buscarPedidos(int limite) {
        return entityManager.createQuery("SELECT p FROM Pedido p ORDER BY p.id", Pedido.class)
            .setMaxResults(limite)
            .getResultList();
    }
}
