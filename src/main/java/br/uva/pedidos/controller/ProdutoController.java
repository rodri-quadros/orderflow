package br.uva.pedidos.controller;

import java.net.URI;

import jakarta.validation.Valid;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import br.uva.pedidos.dto.ProdutoDTO;
import br.uva.pedidos.dto.ProdutoRequest;
import br.uva.pedidos.service.ProdutoService;

@RestController
@RequestMapping("/api/produtos")
public class ProdutoController {

    private final ProdutoService produtoService;

    public ProdutoController(ProdutoService produtoService) {
        this.produtoService = produtoService;
    }

    @PostMapping
    public ResponseEntity<ProdutoDTO> criar(@Valid @RequestBody ProdutoRequest request) {
        ProdutoDTO produto = produtoService.criar(request);
        // A leitura do produto existe apenas nas variantes do experimento de cache.
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
            .path("/{id}/sem-cache").buildAndExpand(produto.id()).toUri();
        return ResponseEntity.created(location).body(produto);
    }

    @GetMapping("/{id}/sem-cache")
    public ProdutoDTO buscarSemCache(@PathVariable Long id) {
        return produtoService.buscarProduto(id);
    }

    @GetMapping("/{id}/com-cache")
    public ProdutoDTO buscarComCache(@PathVariable Long id) {
        return produtoService.buscarProdutoComCache(id);
    }

    @GetMapping("/{id}/com-cache-sync")
    public ProdutoDTO buscarComCacheSync(@PathVariable Long id) {
        return produtoService.buscarProdutoComCacheSync(id);
    }

    @PutMapping("/{id}")
    public ProdutoDTO atualizar(@PathVariable Long id, @Valid @RequestBody ProdutoRequest request) {
        return produtoService.atualizar(id, request);
    }
}
