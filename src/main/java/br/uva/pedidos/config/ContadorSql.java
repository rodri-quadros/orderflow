package br.uva.pedidos.config;

import org.hibernate.resource.jdbc.spi.StatementInspector;

// Conta os SQLs preparados pelo Hibernate na thread da requisição, para medir acessos ao banco
// e evidenciar o N+1 nos experimentos. Registrado em application.yml; instanciado pelo Hibernate.
public class ContadorSql implements StatementInspector {

    private static final ThreadLocal<Integer> CONTADOR = ThreadLocal.withInitial(() -> 0);

    @Override
    public String inspect(String sql) {
        CONTADOR.set(CONTADOR.get() + 1);
        return sql;
    }

    public static void zerar() {
        CONTADOR.set(0);
    }

    public static int total() {
        return CONTADOR.get();
    }

    public static void limpar() {
        CONTADOR.remove();
    }
}
