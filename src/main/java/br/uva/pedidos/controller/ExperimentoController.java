package br.uva.pedidos.controller;

import java.util.List;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import br.uva.pedidos.dto.PedidoExperimentoDTO;
import br.uva.pedidos.dto.PedidoListagemDTO;
import br.uva.pedidos.service.ExperimentoService;

// Variantes de carregamento para o experimento LAZY x EAGER x consultas otimizadas.
// O número de SQLs de cada requisição sai no header X-SQL-Count.
@RestController
@RequestMapping("/api/experimentos/pedidos")
public class ExperimentoController {

    private final ExperimentoService experimentoService;

    public ExperimentoController(ExperimentoService experimentoService) {
        this.experimentoService = experimentoService;
    }

    @GetMapping("/lazy")
    public List<PedidoExperimentoDTO> lazy(@RequestParam(defaultValue = "10") @Min(1) @Max(1000) int limite) {
        return experimentoService.lazy(limite);
    }

    @GetMapping("/eager")
    public List<PedidoExperimentoDTO> eager(@RequestParam(defaultValue = "10") @Min(1) @Max(1000) int limite) {
        return experimentoService.eager(limite);
    }

    @GetMapping("/eager/{id}")
    public PedidoExperimentoDTO eagerPorId(@PathVariable Long id) {
        return experimentoService.eagerPorId(id);
    }

    @GetMapping("/join-fetch")
    public List<PedidoExperimentoDTO> joinFetch(@RequestParam(defaultValue = "10") @Min(1) @Max(1000) int limite) {
        return experimentoService.joinFetch(limite);
    }

    @GetMapping("/nativa")
    public List<PedidoExperimentoDTO> nativa(@RequestParam(defaultValue = "10") @Min(1) @Max(1000) int limite) {
        return experimentoService.nativa(limite);
    }

    @GetMapping("/resumo-lazy")
    public List<PedidoListagemDTO> resumoLazy(@RequestParam(defaultValue = "10") @Min(1) @Max(1000) int limite) {
        return experimentoService.resumoLazy(limite);
    }

    @GetMapping("/resumo-eager")
    public List<PedidoListagemDTO> resumoEager(@RequestParam(defaultValue = "10") @Min(1) @Max(1000) int limite) {
        return experimentoService.resumoEager(limite);
    }
}
