package br.uva.pedidos.dto;

import java.math.BigDecimal;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public record ProdutoRequest(
    @NotBlank @Size(max = 120) String nome,
    @Size(max = 500) String descricao,
    @NotNull @DecimalMin("0.01") @Digits(integer = 8, fraction = 2) BigDecimal preco,
    @NotNull Boolean ativo
) {
}
