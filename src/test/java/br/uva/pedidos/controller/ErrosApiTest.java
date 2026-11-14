package br.uva.pedidos.controller;

import static br.uva.pedidos.DadosTeste.CLIENTE_TIPICO;
import static br.uva.pedidos.DadosTeste.EMAIL_EXISTENTE;
import static br.uva.pedidos.DadosTeste.ID_INEXISTENTE;
import static br.uva.pedidos.DadosTeste.PEDIDO_APROVADO;
import static br.uva.pedidos.DadosTeste.PRODUTO_ATIVO;
import static br.uva.pedidos.DadosTeste.PRODUTO_INATIVO;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.stream.Stream;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

// Todo erro sai como ProblemDetail (RFC 9457) e nenhum expõe SQL, tabelas, classes ou stack trace.
class ErrosApiTest extends TesteIntegracao {

    static Stream<Arguments> erros() {
        return Stream.of(
            Arguments.of("POST", "/api/pedidos", pedidoJson(ID_INEXISTENTE, item(PRODUTO_ATIVO, 1)), 404),
            Arguments.of("POST", "/api/pedidos", pedidoJson(CLIENTE_TIPICO, ""), 400),
            Arguments.of("POST", "/api/pedidos", pedidoJson(CLIENTE_TIPICO, item(PRODUTO_INATIVO, 1)), 422),
            Arguments.of("POST", "/api/pedidos", "{\"clienteId\": 545, \"itens\": [", 400),
            Arguments.of("POST", "/api/pedidos", "{\"clienteId\": \"abc\", \"itens\": []}", 400),
            Arguments.of("PATCH", "/api/pedidos/" + PEDIDO_APROVADO + "/status", "{\"status\": \"CANCELADO\"}", 409),
            Arguments.of("PATCH", "/api/pedidos/" + PEDIDO_APROVADO + "/status", "{\"status\": \"ENTREGUE\"}", 400),
            Arguments.of("POST", "/api/clientes", "{\"nome\": \"X\", \"email\": \"" + EMAIL_EXISTENTE + "\"}", 409),
            Arguments.of("POST", "/api/produtos", "{\"nome\": \"\", \"preco\": 0, \"ativo\": null}", 400),
            Arguments.of("GET", "/api/pedidos/abc", null, 400),
            Arguments.of("GET", "/api/pedidos/" + ID_INEXISTENTE, null, 404),
            Arguments.of("GET", "/api/clientes/1/pedidos?size=500", null, 400),
            Arguments.of("GET", "/api/experimentos/pedidos/lazy?limite=0", null, 400),
            Arguments.of("DELETE", "/api/pedidos/1", null, 405),
            Arguments.of("GET", "/api/nao-existe", null, 404));
    }

    @ParameterizedTest(name = "{0} {1} -> {3}")
    @MethodSource("erros")
    void deveResponderProblemDetailSemDadosInternos(String metodo, String url, String json, int statusEsperado)
            throws Exception {
        var requisicao = MockMvcRequestBuilders.request(metodo, java.net.URI.create(url));
        if (json != null) {
            requisicao.contentType(MediaType.APPLICATION_JSON).content(json);
        }

        MvcResult resultado = mockMvc.perform(requisicao)
            .andExpect(status().is(statusEsperado))
            .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
            .andExpect(jsonPath("$.status").value(statusEsperado))
            .andExpect(jsonPath("$.title").exists())
            .andExpect(jsonPath("$.detail").exists())
            .andReturn();
        assertSemDadosInternos(resultado);
    }
}
