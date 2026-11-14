package br.uva.pedidos.service;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import br.uva.pedidos.dto.ClienteDTO;
import br.uva.pedidos.dto.ClienteRequest;
import br.uva.pedidos.dto.PedidoResumoDTO;
import br.uva.pedidos.entity.Cliente;
import br.uva.pedidos.exception.ConflitoException;
import br.uva.pedidos.exception.RecursoNaoEncontradoException;
import br.uva.pedidos.repository.ClienteRepository;
import br.uva.pedidos.repository.PedidoRepository;

@Service
public class ClienteService {

    private final ClienteRepository clienteRepository;
    private final PedidoRepository pedidoRepository;

    public ClienteService(ClienteRepository clienteRepository, PedidoRepository pedidoRepository) {
        this.clienteRepository = clienteRepository;
        this.pedidoRepository = pedidoRepository;
    }

    @Transactional
    public ClienteDTO criar(ClienteRequest request) {
        if (clienteRepository.existsByEmail(request.email())) {
            throw new ConflitoException("Email já cadastrado");
        }
        try {
            Cliente cliente = new Cliente(request.nome(), request.email(), request.telefone(), LocalDateTime.now());
            return ClienteDTO.de(clienteRepository.save(cliente));
        } catch (DataIntegrityViolationException e) {
            // Outra requisição pode gravar o mesmo email entre o existsByEmail e o INSERT.
            throw new ConflitoException("Email já cadastrado");
        }
    }

    @Transactional(readOnly = true)
    public ClienteDTO buscar(Long id) {
        return clienteRepository.findById(id)
            .map(ClienteDTO::de)
            .orElseThrow(() -> new RecursoNaoEncontradoException("Cliente " + id + " não encontrado"));
    }

    @Transactional(readOnly = true)
    public List<PedidoResumoDTO> listarPedidos(Long clienteId, int pagina, int tamanho) {
        List<PedidoResumoDTO> pedidos =
            pedidoRepository.buscarResumosPorCliente(clienteId, PageRequest.of(pagina, tamanho));
        // A existência do cliente só é conferida quando a lista vem vazia, para que o caminho
        // comum (alvo do experimento de índices) execute uma única consulta.
        if (pedidos.isEmpty() && !clienteRepository.existsById(clienteId)) {
            throw new RecursoNaoEncontradoException("Cliente " + clienteId + " não encontrado");
        }
        return pedidos;
    }
}
