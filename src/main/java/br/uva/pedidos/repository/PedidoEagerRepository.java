package br.uva.pedidos.repository;

import java.util.List;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;

import br.uva.pedidos.entity.PedidoEager;

public interface PedidoEagerRepository extends JpaRepository<PedidoEager, Long> {

    List<PedidoEager> findAllByOrderByIdAsc(Limit limite);
}
