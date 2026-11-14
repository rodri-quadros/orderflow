package br.uva.pedidos.controller;

import static br.uva.pedidos.DadosTeste.CLIENTE_TIPICO;
import static br.uva.pedidos.DadosTeste.ID_INEXISTENTE;
import static br.uva.pedidos.DadosTeste.PEDIDO_APROVADO;
import static br.uva.pedidos.DadosTeste.PEDIDO_PENDENTE;
import static br.uva.pedidos.DadosTeste.PRECO_PRODUTO_ATIVO;
import static br.uva.pedidos.DadosTeste.PRECO_PRODUTO_ATIVO_2;
import static br.uva.pedidos.DadosTeste.PRODUTO_ATIVO;
import static br.uva.pedidos.DadosTeste.PRODUTO_ATIVO_2;
import static br.uva.pedidos.DadosTeste.PRODUTO_INATIVO;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;

import jakarta.persistence.EntityManager;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;

import com.jayway.jsonpath.JsonPath;

import br.uva.pedidos.entity.StatusPedido;

class PedidoControllerTest extends TesteIntegracao {

    @Autowired
    private EntityManager entityManager;

    private static String statusJson(String status) {
        return """
            {"status": "%s"}""".formatted(status);
    }

    @Test
    @Transactional
    void deveCriarPedidoComPrecoDoProdutoEValorTotalCalculado() throws Exception {
        MvcResult resultado = post("/api/pedidos", pedidoJson(CLIENTE_TIPICO,
                item(PRODUTO_ATIVO, 2) + "," + item(PRODUTO_ATIVO_2, 1)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.status").value("PENDENTE"))
            .andExpect(jsonPath("$.cliente.id").value(CLIENTE_TIPICO))
            .andExpect(jsonPath("$.itens[0].precoUnitario").value(PRECO_PRODUTO_ATIVO.doubleValue()))
            .andExpect(jsonPath("$.itens[1].precoUnitario").value(PRECO_PRODUTO_ATIVO_2.doubleValue()))
            .andReturn();

        BigDecimal esperado = PRECO_PRODUTO_ATIVO.multiply(BigDecimal.TWO).add(PRECO_PRODUTO_ATIVO_2);
        assertThat(new BigDecimal(JsonPath.read(corpo(resultado), "$.valorTotal").toString())).isEqualByComparingTo(esperado);
        Integer id = JsonPath.read(corpo(resultado), "$.id");
        assertThat(resultado.getResponse().getHeader("Location")).endsWith("/api/pedidos/" + id);
    }

    @Test
    void deveBuscarPedidoComClienteEItensEmUmaConsulta() throws Exception {
        MvcResult resultado = get("/api/pedidos/" + PEDIDO_PENDENTE)
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("PENDENTE"))
            .andExpect(jsonPath("$.cliente.nome").exists())
            .andExpect(jsonPath("$.itens.length()").value(1))
            .andReturn();
        assertThat(sqlCount(resultado)).isEqualTo(1);
    }

    @ParameterizedTest
    @EnumSource(value = StatusPedido.class, names = {"APROVADO", "CANCELADO"})
    @Transactional
    void deveAprovarOuCancelarPedidoPendente(StatusPedido novo) throws Exception {
        patch("/api/pedidos/" + PEDIDO_PENDENTE + "/status", statusJson(novo.name()))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value(novo.name()));
    }

    @Test
    void deveRetornar409AoAprovarPedidoJaAprovado() throws Exception {
        MvcResult resultado = patch("/api/pedidos/" + PEDIDO_APROVADO + "/status", statusJson("APROVADO"))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.detail").value("Transição de status inválida: APROVADO -> APROVADO"))
            .andReturn();
        assertSemDadosInternos(resultado);
    }

    @Test
    void deveRetornar404AoCriarPedidoDeClienteInexistente() throws Exception {
        post("/api/pedidos", pedidoJson(ID_INEXISTENTE, item(PRODUTO_ATIVO, 1))).andExpect(status().isNotFound());
    }

    @Test
    void deveRetornar400AoCriarPedidoSemItens() throws Exception {
        post("/api/pedidos", pedidoJson(CLIENTE_TIPICO, ""))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.erros[0].campo").value("itens"));
    }

    @Test
    void deveRetornar400ParaItemSemQuantidadeOuComQuantidadeZero() throws Exception {
        post("/api/pedidos", pedidoJson(CLIENTE_TIPICO, """
                {"produtoId": %d}""".formatted(PRODUTO_ATIVO)))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.erros[0].campo").value("itens[0].quantidade"));
        post("/api/pedidos", pedidoJson(CLIENTE_TIPICO, item(PRODUTO_ATIVO, 0)))
            .andExpect(status().isBadRequest());
    }

    @Test
    void deveRetornar404AoCriarPedidoComProdutoInexistente() throws Exception {
        post("/api/pedidos", pedidoJson(CLIENTE_TIPICO, item(ID_INEXISTENTE, 1))).andExpect(status().isNotFound());
    }

    @Test
    void deveRetornar422AoCriarPedidoComProdutoInativo() throws Exception {
        post("/api/pedidos", pedidoJson(CLIENTE_TIPICO, item(PRODUTO_INATIVO, 1)))
            .andExpect(status().isUnprocessableContent());
    }

    @Test
    void deveRetornar422AoRepetirProdutoNoPedido() throws Exception {
        post("/api/pedidos", pedidoJson(CLIENTE_TIPICO, item(PRODUTO_ATIVO, 1) + "," + item(PRODUTO_ATIVO, 2)))
            .andExpect(status().isUnprocessableContent());
    }

    @Test
    @Transactional
    void deveManterOPrecoHistoricoDoItemAposReajusteDoProduto() throws Exception {
        // dado um pedido feito com o preço atual
        MvcResult criado = post("/api/pedidos", pedidoJson(CLIENTE_TIPICO, item(PRODUTO_ATIVO, 1)))
            .andExpect(status().isCreated()).andReturn();
        Integer pedidoId = JsonPath.read(corpo(criado), "$.id");

        // quando o preço do produto é reajustado
        put("/api/produtos/" + PRODUTO_ATIVO, """
                {"nome": "Produto 10", "descricao": "reajuste", "preco": 1599.90, "ativo": true}""")
            .andExpect(status().isOk());
        entityManager.flush();
        entityManager.clear();   // força a próxima leitura a vir do banco

        // então o item do pedido mantém o preço antigo e o produto mostra o novo
        get("/api/pedidos/" + pedidoId)
            .andExpect(jsonPath("$.itens[0].precoUnitario").value(PRECO_PRODUTO_ATIVO.doubleValue()));
        get("/api/produtos/" + PRODUTO_ATIVO + "/sem-cache")
            .andExpect(jsonPath("$.preco").value(1599.90));
    }
}
