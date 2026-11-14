package br.uva.pedidos.service;

import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import br.uva.pedidos.dto.ProdutoDTO;
import br.uva.pedidos.dto.ProdutoRequest;
import br.uva.pedidos.entity.Produto;
import br.uva.pedidos.exception.RecursoNaoEncontradoException;
import br.uva.pedidos.repository.ProdutoRepository;

@Service
public class ProdutoService {

    private final ProdutoRepository produtoRepository;

    public ProdutoService(ProdutoRepository produtoRepository) {
        this.produtoRepository = produtoRepository;
    }

    // Cenário A: consulta o banco a cada chamada.
    @Transactional(readOnly = true)
    public ProdutoDTO buscarProduto(Long id) {
        return produtoRepository.buscarDTO(id)
            .orElseThrow(() -> naoEncontrado(id));
    }

    // Cenário B: mesma consulta, mas o resultado fica no Redis até o TTL ou o próximo PUT.
    // Chamado direto pelo controller: uma chamada interna (this.) ignoraria o proxy do cache.
    // O 404 lança exceção, então produto inexistente nunca vai para o cache.
    @Cacheable(value = "produtos", key = "#id")
    @Transactional(readOnly = true)
    public ProdutoDTO buscarProdutoComCache(Long id) {
        return produtoRepository.buscarDTO(id)
            .orElseThrow(() -> naoEncontrado(id));
    }

    @Transactional
    public ProdutoDTO criar(ProdutoRequest request) {
        Produto produto = new Produto(request.nome(), request.descricao(), request.preco());
        produto.setAtivo(request.ativo());
        return ProdutoDTO.de(produtoRepository.save(produto));
    }

    // Variante com sync = true, para estudar o efeito manada (vários MISS simultâneos da mesma chave).
    // O Spring trata sync como dica e delega ao provedor: no Spring Data Redis 4.1, com o cache writer sem
    // trava (configuração atual), o RedisCache não sincroniza nada; só um writer com enableLocking() serializa,
    // e a trava dele é distribuída (chave produtos~lock no Redis) e vale para o cache inteiro, não por chave.
    @Cacheable(value = "produtos", key = "#id", sync = true)
    @Transactional(readOnly = true)
    public ProdutoDTO buscarProdutoComCacheSync(Long id) {
        return produtoRepository.buscarDTO(id)
            .orElseThrow(() -> naoEncontrado(id));
    }

    // Evict em vez de @CachePut: o próximo GET recarrega do banco, e uma escrita que falhe
    // não deixa no cache um valor que não existe no banco.
    @CacheEvict(value = "produtos", key = "#id")
    @Transactional
    public ProdutoDTO atualizar(Long id, ProdutoRequest request) {
        Produto produto = produtoRepository.findById(id)
            .orElseThrow(() -> naoEncontrado(id));
        produto.setNome(request.nome());
        produto.setDescricao(request.descricao());
        produto.setPreco(request.preco());
        produto.setAtivo(request.ativo());
        return ProdutoDTO.de(produto);
    }

    private RecursoNaoEncontradoException naoEncontrado(Long id) {
        return new RecursoNaoEncontradoException("Produto " + id + " não encontrado");
    }
}
