package br.uva.pedidos.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

import br.uva.pedidos.dto.ClienteRequest;
import br.uva.pedidos.exception.ConflitoException;
import br.uva.pedidos.repository.ClienteRepository;
import br.uva.pedidos.repository.PedidoRepository;

@ExtendWith(MockitoExtension.class)
class ClienteServiceTest {

    private static final ClienteRequest CLIENTE = new ClienteRequest("Maria", "maria@exemplo.com", null);

    @Mock
    private ClienteRepository clienteRepository;
    @Mock
    private PedidoRepository pedidoRepository;
    @InjectMocks
    private ClienteService clienteService;

    @Test
    void deveLancarConflitoQuandoEmailJaEstaCadastrado() {
        when(clienteRepository.existsByEmail(CLIENTE.email())).thenReturn(true);

        assertThatThrownBy(() -> clienteService.criar(CLIENTE)).isInstanceOf(ConflitoException.class);
        verify(clienteRepository, never()).save(any());
    }

    @Test
    void deveConverterViolacaoDeUnicidadeDoBancoEmConflito() {
        // Corrida: outra requisição grava o mesmo email entre o existsByEmail e o INSERT.
        when(clienteRepository.existsByEmail(CLIENTE.email())).thenReturn(false);
        when(clienteRepository.save(any())).thenThrow(new DataIntegrityViolationException("cliente_email_key"));

        assertThatThrownBy(() -> clienteService.criar(CLIENTE))
            .isInstanceOf(ConflitoException.class)
            .hasMessage("Email já cadastrado");
    }
}
