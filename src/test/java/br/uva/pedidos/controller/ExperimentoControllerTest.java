package br.uva.pedidos.controller;

import static br.uva.pedidos.DadosTeste.PEDIDO_APROVADO;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.test.web.servlet.MvcResult;

// Contagens de SQL observadas na Etapa 6 com limite=10 (10 pedidos, 10 clientes distintos):
// LAZY e EAGER em lista = 1 + 10 (itens) + 10 (clientes); JOIN FETCH = 2; nativa = 1.
class ExperimentoControllerTest extends TesteIntegracao {

    private static final String BASE = "/api/experimentos/pedidos/";

    @ParameterizedTest(name = "{0} -> {1} SQLs")
    @CsvSource({
        "lazy?limite=10,         21",
        "eager?limite=10,        21",
        "join-fetch?limite=10,   2",
        "nativa?limite=10,       1",
        "resumo-lazy?limite=10,  11",
        "resumo-eager?limite=10, 21"
    })
    void deveExecutarAQuantidadeDeSqlEsperadaPorEstrategia(String rota, int sqlsEsperados) throws Exception {
        MvcResult resultado = get(BASE + rota).andExpect(status().isOk()).andReturn();

        assertThat(sqlCount(resultado)).isEqualTo(sqlsEsperados);
    }

    @Test
    void deveCarregarPedidoEagerPorIdComUmaConsulta() throws Exception {
        MvcResult resultado = get(BASE + "eager/" + PEDIDO_APROVADO).andExpect(status().isOk()).andReturn();

        assertThat(sqlCount(resultado)).isEqualTo(1);
    }

    @Test
    void deveDevolverOMesmoJsonEmTodasAsEstrategias() throws Exception {
        String lazy = corpo(get(BASE + "lazy?limite=10").andReturn());

        for (String estrategia : new String[] {"eager", "join-fetch", "nativa"}) {
            assertThat(corpo(get(BASE + estrategia + "?limite=10").andReturn())).as(estrategia).isEqualTo(lazy);
        }
        assertThat(corpo(get(BASE + "resumo-eager?limite=10").andReturn()))
            .isEqualTo(corpo(get(BASE + "resumo-lazy?limite=10").andReturn()));
    }

    @Test
    void deveRetornar400ParaLimiteForaDoIntervalo() throws Exception {
        get(BASE + "nativa?limite=0").andExpect(status().isBadRequest());
        get(BASE + "nativa?limite=1001").andExpect(status().isBadRequest());
    }
}
