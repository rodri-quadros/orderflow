package br.uva.pedidos.dto;

import java.time.LocalDateTime;

import br.uva.pedidos.entity.Cliente;

public record ClienteDTO(
    Long id,
    String nome,
    String email,
    String telefone,
    LocalDateTime dataCadastro
) {

    public static ClienteDTO de(Cliente cliente) {
        return new ClienteDTO(cliente.getId(), cliente.getNome(), cliente.getEmail(),
            cliente.getTelefone(), cliente.getDataCadastro());
    }
}
