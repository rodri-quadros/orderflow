package br.uva.pedidos.controller;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

// Base dos testes HTTP: contexto completo contra o PostgreSQL e o Redis do Docker Compose (precisam estar no ar).
// O MockMvc passa pelos filtros da aplicação, então o header X-SQL-Count está disponível.
@SpringBootTest
@AutoConfigureMockMvc
abstract class TesteIntegracao {

    // Fragmentos que só apareceriam se um erro vazasse detalhes internos. Nomes de tabela comuns ao domínio
    // ("pedido", "produto") aparecem legitimamente nas mensagens e nas URLs; por isso a lista usa os
    // identificadores que só existem no banco (item_pedido, *_pkey, *_key) e termos de SQL e de Java.
    private static final String[] FRAGMENTOS_INTERNOS = {
        "SQL", "select", "insert", "update ", "item_pedido", "_pkey", "_key", "constraint", "relation",
        "Exception", "org.", "java.", "at br.", "trace"
    };

    @Autowired
    protected MockMvc mockMvc;

    protected ResultActions get(String url) throws Exception {
        return mockMvc.perform(MockMvcRequestBuilders.get(url));
    }

    protected ResultActions post(String url, String json) throws Exception {
        return mockMvc.perform(MockMvcRequestBuilders.post(url).contentType(MediaType.APPLICATION_JSON).content(json));
    }

    protected ResultActions put(String url, String json) throws Exception {
        return mockMvc.perform(MockMvcRequestBuilders.put(url).contentType(MediaType.APPLICATION_JSON).content(json));
    }

    protected ResultActions patch(String url, String json) throws Exception {
        return mockMvc.perform(MockMvcRequestBuilders.patch(url).contentType(MediaType.APPLICATION_JSON).content(json));
    }

    protected static String corpo(MvcResult resultado) throws Exception {
        return resultado.getResponse().getContentAsString(StandardCharsets.UTF_8);
    }

    protected static int sqlCount(MvcResult resultado) {
        return Integer.parseInt(resultado.getResponse().getHeader("X-SQL-Count"));
    }

    protected static void assertSemDadosInternos(MvcResult resultado) throws Exception {
        assertThat(corpo(resultado)).doesNotContain(FRAGMENTOS_INTERNOS);
    }

    protected static String pedidoJson(long clienteId, String itens) {
        return """
            {"clienteId": %d, "itens": [%s]}""".formatted(clienteId, itens);
    }

    protected static String item(long produtoId, int quantidade) {
        return """
            {"produtoId": %d, "quantidade": %d}""".formatted(produtoId, quantidade);
    }
}
