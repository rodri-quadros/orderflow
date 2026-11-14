package br.uva.pedidos.controller;

import static br.uva.pedidos.DadosTeste.ID_INEXISTENTE;
import static br.uva.pedidos.DadosTeste.PRODUTO_ATIVO;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;

import com.jayway.jsonpath.JsonPath;

class ProdutoControllerTest extends TesteIntegracao {

    private static String produtoJson(String preco) {
        return """
            {"nome": "Produto de Teste", "descricao": "Criado pelo teste", "preco": %s, "ativo": true}""".formatted(preco);
    }

    @Test
    @Transactional
    void deveCriarProdutoERetornar201ComLocation() throws Exception {
        MvcResult resultado = post("/api/produtos", produtoJson("99.90"))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.preco").value(99.90))
            .andExpect(jsonPath("$.ativo").value(true))
            .andReturn();

        Integer id = JsonPath.read(corpo(resultado), "$.id");
        assertThat(resultado.getResponse().getHeader("Location")).endsWith("/api/produtos/" + id + "/sem-cache");
    }

    @Test
    void deveBuscarProdutoSemCacheComUmaConsulta() throws Exception {
        MvcResult resultado = get("/api/produtos/" + PRODUTO_ATIVO + "/sem-cache")
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.nome").value("Produto 10"))
            .andExpect(jsonPath("$.preco").value(1419.87))
            .andReturn();
        assertThat(sqlCount(resultado)).isEqualTo(1);
    }

    @Test
    @Transactional
    void deveAtualizarProduto() throws Exception {
        put("/api/produtos/" + PRODUTO_ATIVO, produtoJson("1500.00"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.nome").value("Produto de Teste"))
            .andExpect(jsonPath("$.preco").value(1500.00));
    }

    @ParameterizedTest
    @ValueSource(strings = {"0", "-5", "10.999", "123456789.00"})
    void deveRetornar400ParaPrecoInvalido(String preco) throws Exception {
        post("/api/produtos", produtoJson(preco))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.erros[0].campo").value("preco"));
    }

    @Test
    void deveRetornar404ParaProdutoInexistente() throws Exception {
        get("/api/produtos/" + ID_INEXISTENTE + "/sem-cache").andExpect(status().isNotFound());
        put("/api/produtos/" + ID_INEXISTENTE, produtoJson("10.00")).andExpect(status().isNotFound());
    }
}
