package br.uva.pedidos;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;

// Confirma que o statement_timeout configurado no Hikari (application.yml) chega às conexões da
// aplicação: consultas travadas são canceladas pelo banco em vez de prender o pool nos testes de carga.
@SpringBootTest
class StatementTimeoutTest {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Test
    void conexaoDaAplicacaoUsaOTimeoutConfigurado() {
        assertThat(jdbcTemplate.queryForObject("SHOW statement_timeout", String.class)).isEqualTo("10s");
    }

    // Leva 10 s: desligado por padrão. Rodar com ./mvnw verify -Dtestes.lentos=true
    @Test
    @EnabledIfSystemProperty(named = "testes.lentos", matches = "true")
    void consultaAcimaDoLimiteECancelada() {
        assertThatThrownBy(() -> jdbcTemplate.queryForObject("SELECT pg_sleep(11)", Object.class))
            .isInstanceOf(DataAccessException.class)
            .hasMessageContaining("statement timeout");
    }
}
