package br.uva.pedidos.entity;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

class StatusPedidoTest {

    @ParameterizedTest(name = "{0} -> {1}: {2}")
    @CsvSource({
        "PENDENTE,  PENDENTE,  false",
        "PENDENTE,  APROVADO,  true",
        "PENDENTE,  CANCELADO, true",
        "APROVADO,  PENDENTE,  false",
        "APROVADO,  APROVADO,  false",
        "APROVADO,  CANCELADO, false",
        "CANCELADO, PENDENTE,  false",
        "CANCELADO, APROVADO,  false",
        "CANCELADO, CANCELADO, false"
    })
    void devePermitirSomenteAprovarOuCancelarPedidoPendente(StatusPedido atual, StatusPedido novo, boolean permitido) {
        assertThat(atual.podeMudarPara(novo)).isEqualTo(permitido);
    }
}
