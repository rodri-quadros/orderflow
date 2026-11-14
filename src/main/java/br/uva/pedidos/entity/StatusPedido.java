package br.uva.pedidos.entity;

public enum StatusPedido {
    PENDENTE,
    APROVADO,
    CANCELADO;

    // Única fonte da regra de transição: só um pedido pendente pode ser aprovado ou cancelado.
    public boolean podeMudarPara(StatusPedido novo) {
        return this == PENDENTE && (novo == APROVADO || novo == CANCELADO);
    }
}
