package br.uva.pedidos.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import br.uva.pedidos.dto.ProdutoDTO;
import br.uva.pedidos.entity.Produto;

public interface ProdutoRepository extends JpaRepository<Produto, Long> {

    // Projeção direto em DTO: 1 consulta e nenhuma entidade gerenciada.
    @Query("""
        SELECT new br.uva.pedidos.dto.ProdutoDTO(p.id, p.nome, p.descricao, p.preco, p.ativo)
        FROM Produto p
        WHERE p.id = :id
        """)
    Optional<ProdutoDTO> buscarDTO(Long id);
}
