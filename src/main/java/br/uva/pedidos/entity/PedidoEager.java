package br.uva.pedidos.entity;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

import org.hibernate.annotations.Immutable;

// Mesma tabela de Pedido, mas com relacionamentos EAGER. Um mapeamento só aceita um FetchType;
// com duas entidades as versões LAZY e EAGER rodam lado a lado sem recompilar. Somente leitura,
// usada apenas pelo experimento: a API continua usando Pedido (LAZY).
@Entity
@Immutable
@Table(name = "pedido")
public class PedidoEager {

    @Id
    private Long id;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "cliente_id", nullable = false)
    private Cliente cliente;

    @Column(name = "data_pedido", nullable = false)
    private LocalDateTime dataPedido;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    private StatusPedido status;

    @Column(name = "valor_total", nullable = false, precision = 12, scale = 2)
    private BigDecimal valorTotal;

    // Unidirecional, reaproveitando ItemPedido; a coluna pedido_id continua sendo escrita só por Pedido.
    @OneToMany(fetch = FetchType.EAGER)
    @JoinColumn(name = "pedido_id", insertable = false, updatable = false)
    private List<ItemPedido> itens = new ArrayList<>();

    protected PedidoEager() {
    }

    public Long getId() {
        return id;
    }

    public Cliente getCliente() {
        return cliente;
    }

    public LocalDateTime getDataPedido() {
        return dataPedido;
    }

    public StatusPedido getStatus() {
        return status;
    }

    public BigDecimal getValorTotal() {
        return valorTotal;
    }

    public List<ItemPedido> getItens() {
        return Collections.unmodifiableList(itens);
    }
}
