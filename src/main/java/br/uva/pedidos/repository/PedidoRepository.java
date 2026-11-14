package br.uva.pedidos.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import br.uva.pedidos.dto.PedidoResumoDTO;
import br.uva.pedidos.entity.Pedido;

public interface PedidoRepository extends JpaRepository<Pedido, Long> {

    // Alvo do experimento de índices (WHERE cliente_id ... ORDER BY data_pedido DESC).
    // Retornar List em vez de Page evita a consulta extra de count.
    @Query("""
        SELECT new br.uva.pedidos.dto.PedidoResumoDTO(p.id, p.dataPedido, p.status, p.valorTotal)
        FROM Pedido p
        WHERE p.cliente.id = :clienteId
        ORDER BY p.dataPedido DESC
        """)
    List<PedidoResumoDTO> buscarResumosPorCliente(Long clienteId, Pageable pageable);

    @Query("""
        SELECT p FROM Pedido p
        JOIN FETCH p.cliente
        JOIN FETCH p.itens i
        JOIN FETCH i.produto
        WHERE p.id = :id
        ORDER BY i.id
        """)
    Optional<Pedido> buscarComItens(Long id);
}
