package br.uva.pedidos.controller;

import java.net.URI;

import jakarta.validation.Valid;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import br.uva.pedidos.dto.AlterarStatusRequest;
import br.uva.pedidos.dto.PedidoDTO;
import br.uva.pedidos.dto.PedidoRequest;
import br.uva.pedidos.service.PedidoService;

@RestController
@RequestMapping("/api/pedidos")
public class PedidoController {

    private final PedidoService pedidoService;

    public PedidoController(PedidoService pedidoService) {
        this.pedidoService = pedidoService;
    }

    @PostMapping
    public ResponseEntity<PedidoDTO> criar(@Valid @RequestBody PedidoRequest request) {
        PedidoDTO pedido = pedidoService.criar(request);
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
            .path("/{id}").buildAndExpand(pedido.id()).toUri();
        return ResponseEntity.created(location).body(pedido);
    }

    @GetMapping("/{id}")
    public PedidoDTO buscar(@PathVariable Long id) {
        return pedidoService.buscar(id);
    }

    @PatchMapping("/{id}/status")
    public PedidoDTO alterarStatus(@PathVariable Long id, @Valid @RequestBody AlterarStatusRequest request) {
        return pedidoService.alterarStatus(id, request.status());
    }
}
