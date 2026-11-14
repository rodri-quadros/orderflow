package br.uva.pedidos.controller;

import static br.uva.pedidos.DadosTeste.CLIENTE_MUITOS_PEDIDOS;
import static br.uva.pedidos.DadosTeste.CLIENTE_TIPICO;
import static br.uva.pedidos.DadosTeste.EMAIL_EXISTENTE;
import static br.uva.pedidos.DadosTeste.ID_INEXISTENTE;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;

import com.jayway.jsonpath.JsonPath;

class ClienteControllerTest extends TesteIntegracao {

    @Test
    @Transactional
    void deveCriarClienteERetornar201ComLocation() throws Exception {
        MvcResult resultado = post("/api/clientes", """
                {"nome": "Cliente de Teste", "email": "teste.integracao@exemplo.com", "telefone": "(21) 90000-0000"}""")
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.email").value("teste.integracao@exemplo.com"))
            .andReturn();

        Integer id = JsonPath.read(corpo(resultado), "$.id");
        assertThat(resultado.getResponse().getHeader("Location")).endsWith("/api/clientes/" + id);
    }

    @Test
    void deveBuscarClientePorId() throws Exception {
        get("/api/clientes/" + CLIENTE_TIPICO)
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.nome").value("Cliente 545"))
            .andExpect(jsonPath("$.email").value("cliente545@exemplo.com"));
    }

    @Test
    void deveListarPedidosDoClienteDoMaisRecenteParaOMaisAntigoComUmaConsulta() throws Exception {
        MvcResult resultado = get("/api/clientes/" + CLIENTE_MUITOS_PEDIDOS + "/pedidos?page=0&size=20")
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(20))
            .andReturn();

        List<String> datas = JsonPath.read(corpo(resultado), "$[*].dataPedido");
        assertThat(datas).isSortedAccordingTo((a, b) -> b.compareTo(a));
        assertThat(sqlCount(resultado)).isEqualTo(1);
    }

    @Test
    void deveRetornarPaginaVaziaQuandoOClienteTemMenosPedidos() throws Exception {
        get("/api/clientes/" + CLIENTE_TIPICO + "/pedidos?page=2&size=20")
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(0))
            .andExpect(header().string("X-SQL-Count", "2"));   // lista vazia: confere se o cliente existe
    }

    @Test
    void deveRetornar409AoCadastrarEmailDuplicado() throws Exception {
        MvcResult resultado = post("/api/clientes", """
                {"nome": "Duplicado", "email": "%s"}""".formatted(EMAIL_EXISTENTE))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.detail").value("Email já cadastrado"))
            .andReturn();
        assertSemDadosInternos(resultado);
    }

    @Test
    void deveRetornar400ComOCampoInvalidoQuandoEmailEhInvalido() throws Exception {
        post("/api/clientes", """
                {"nome": "Sem email válido", "email": "abc"}""")
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.erros[0].campo").value("email"));
    }

    @Test
    void deveRetornar404ParaClienteInexistente() throws Exception {
        get("/api/clientes/" + ID_INEXISTENTE).andExpect(status().isNotFound());
        get("/api/clientes/" + ID_INEXISTENTE + "/pedidos").andExpect(status().isNotFound());
    }

    @ParameterizedTest
    @ValueSource(strings = {"size=101", "size=0", "page=-1", "size=dez"})
    void deveRetornar400ParaPaginacaoForaDosLimites(String parametro) throws Exception {
        get("/api/clientes/" + CLIENTE_MUITOS_PEDIDOS + "/pedidos?" + parametro)
            .andExpect(status().isBadRequest());
    }
}
