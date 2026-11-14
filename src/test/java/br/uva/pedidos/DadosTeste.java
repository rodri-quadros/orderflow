package br.uva.pedidos;

import java.math.BigDecimal;

// Ids da base determinística gerada por db/init/03_dados.sql (setseed 0.42), descobertos por consulta.
// Único lugar com ids de teste: se a carga mudar, só este arquivo muda.
public final class DadosTeste {

    public static final long CLIENTE_MUITOS_PEDIDOS = 1L;      // 225 pedidos
    public static final long CLIENTE_TIPICO = 545L;            // 9 pedidos (mediana)
    public static final String EMAIL_EXISTENTE = "cliente1@exemplo.com";

    public static final long PRODUTO_ATIVO = 10L;
    public static final BigDecimal PRECO_PRODUTO_ATIVO = new BigDecimal("1419.87");
    public static final long PRODUTO_ATIVO_2 = 20L;
    public static final BigDecimal PRECO_PRODUTO_ATIVO_2 = new BigDecimal("1236.44");
    public static final long PRODUTO_INATIVO = 5L;

    // Reservado aos testes de cache, que fazem commit (o evict só acontece após o commit).
    public static final long PRODUTO_CACHE = 40L;
    public static final String PRODUTO_CACHE_JSON = """
        {"nome":"Produto 40","descricao":"Descrição do produto 40 para testes de desempenho","preco":33.43,"ativo":true}""";

    public static final long PEDIDO_PENDENTE = 3L;
    public static final long PEDIDO_APROVADO = 1L;

    public static final long ID_INEXISTENTE = 999_999L;

    private DadosTeste() {
    }
}
