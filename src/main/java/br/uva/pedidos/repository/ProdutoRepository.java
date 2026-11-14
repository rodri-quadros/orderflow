package br.uva.pedidos.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import br.uva.pedidos.entity.Produto;

public interface ProdutoRepository extends JpaRepository<Produto, Long> {
}
