package br.uva.pedidos.controller;

import java.net.URI;
import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import br.uva.pedidos.dto.ClienteDTO;
import br.uva.pedidos.dto.ClienteRequest;
import br.uva.pedidos.dto.PedidoResumoDTO;
import br.uva.pedidos.service.ClienteService;

// Sem @Validated na classe: os @Min/@Max dos parâmetros são validados pela validação nativa do
// Spring MVC (HandlerMethodValidationException -> 400). Com @Validated, um proxy AOP lançaria
// ConstraintViolationException no lugar.
@RestController
@RequestMapping("/api/clientes")
public class ClienteController {

    private final ClienteService clienteService;

    public ClienteController(ClienteService clienteService) {
        this.clienteService = clienteService;
    }

    @PostMapping
    public ResponseEntity<ClienteDTO> criar(@Valid @RequestBody ClienteRequest request) {
        ClienteDTO cliente = clienteService.criar(request);
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
            .path("/{id}").buildAndExpand(cliente.id()).toUri();
        return ResponseEntity.created(location).body(cliente);
    }

    @GetMapping("/{id}")
    public ClienteDTO buscar(@PathVariable Long id) {
        return clienteService.buscar(id);
    }

    @GetMapping("/{id}/pedidos")
    public List<PedidoResumoDTO> listarPedidos(
            @PathVariable Long id,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {
        return clienteService.listarPedidos(id, page, size);
    }
}
