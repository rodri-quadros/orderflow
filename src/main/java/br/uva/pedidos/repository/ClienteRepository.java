package br.uva.pedidos.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import br.uva.pedidos.entity.Cliente;

public interface ClienteRepository extends JpaRepository<Cliente, Long> {
}
