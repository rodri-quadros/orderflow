package br.uva.pedidos.controller;

import static br.uva.pedidos.DadosTeste.ID_INEXISTENTE;
import static br.uva.pedidos.DadosTeste.PRODUTO_CACHE;
import static br.uva.pedidos.DadosTeste.PRODUTO_CACHE_JSON;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.web.servlet.MvcResult;

// Sem @Transactional: o evict é transactionAware e só acontece após o commit do PUT. Por isso o estado é
// restaurado no @AfterEach (preço original via PUT, que também invalida a chave). Usa o Redis da aplicação.
class CacheIntegracaoTest extends TesteIntegracao {

    private static final String CHAVE = "produtos::" + PRODUTO_CACHE;
    private static final String COM_CACHE = "/api/produtos/" + PRODUTO_CACHE + "/com-cache";

    @Autowired
    private StringRedisTemplate redis;

    @BeforeEach
    void partirDeCacheVazio() {
        redis.delete(CHAVE);
    }

    @AfterEach
    void restaurarProduto() throws Exception {
        put("/api/produtos/" + PRODUTO_CACHE, PRODUTO_CACHE_JSON).andExpect(status().isOk());
        redis.delete(CHAVE);
    }

    @Test
    void deveFazerMissDepoisHitEInvalidarNoPut() throws Exception {
        // MISS: consulta o banco e grava a chave
        assertThat(sqlCount(get(COM_CACHE).andExpect(jsonPath("$.preco").value(33.43)).andReturn())).isEqualTo(1);
        assertThat(redis.hasKey(CHAVE)).isTrue();

        // HIT: responde do Redis, sem SQL
        assertThat(sqlCount(get(COM_CACHE).andReturn())).isZero();

        // PUT: a chave sai após o commit
        put("/api/produtos/" + PRODUTO_CACHE, PRODUTO_CACHE_JSON.replace("33.43", "43.43")).andExpect(status().isOk());
        assertThat(redis.hasKey(CHAVE)).isFalse();

        // próxima leitura: MISS com o preço novo
        MvcResult depois = get(COM_CACHE).andExpect(jsonPath("$.preco").value(43.43)).andReturn();
        assertThat(sqlCount(depois)).isEqualTo(1);
    }

    @Test
    void deveDevolverNoHitOMesmoJsonDoBanco() throws Exception {
        get(COM_CACHE);
        MvcResult hit = get(COM_CACHE).andReturn();
        MvcResult banco = get("/api/produtos/" + PRODUTO_CACHE + "/sem-cache").andReturn();

        assertThat(sqlCount(hit)).isZero();
        assertThat(corpo(hit)).isEqualTo(corpo(banco));
    }

    @Test
    void deveCompartilharOCacheEntreAsVariantesComESemSync() throws Exception {
        // MISS pela variante sync grava a mesma chave; a variante comum lê como HIT, e vice-versa.
        assertThat(sqlCount(get(COM_CACHE + "-sync").andExpect(jsonPath("$.preco").value(33.43)).andReturn())).isEqualTo(1);
        assertThat(redis.hasKey(CHAVE)).isTrue();
        assertThat(sqlCount(get(COM_CACHE).andReturn())).isZero();
        assertThat(sqlCount(get(COM_CACHE + "-sync").andReturn())).isZero();
    }

    @Test
    void deveRetornar404SemCriarChaveParaProdutoInexistente() throws Exception {
        get("/api/produtos/" + ID_INEXISTENTE + "/com-cache").andExpect(status().isNotFound());
        get("/api/produtos/" + ID_INEXISTENTE + "/com-cache-sync").andExpect(status().isNotFound());

        assertThat(redis.hasKey("produtos::" + ID_INEXISTENTE)).isFalse();
    }
}
