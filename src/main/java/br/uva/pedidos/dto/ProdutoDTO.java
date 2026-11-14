package br.uva.pedidos.dto;

import java.math.BigDecimal;

import br.uva.pedidos.entity.Produto;

public record ProdutoDTO(
    Long id,
    String nome,
    String descricao,
    BigDecimal preco,
    boolean ativo
) {

    public static ProdutoDTO de(Produto produto) {
        return new ProdutoDTO(produto.getId(), produto.getNome(), produto.getDescricao(),
            produto.getPreco(), produto.isAtivo());
    }
}
