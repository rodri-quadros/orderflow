package br.uva.pedidos.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import br.uva.pedidos.entity.Pedido;

public interface PedidoRepository extends JpaRepository<Pedido, Long> {
}
