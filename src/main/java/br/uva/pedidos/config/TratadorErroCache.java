package br.uva.pedidos.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cache.Cache;
import org.springframework.cache.interceptor.CacheErrorHandler;

// Degradação graciosa: se o Redis falhar, a requisição segue para o banco em vez de virar 500.
// Uma falha no GET vira MISS; uma falha no evict pode deixar o valor antigo até o TTL expirar.
public class TratadorErroCache implements CacheErrorHandler {

    private static final Logger log = LoggerFactory.getLogger(TratadorErroCache.class);

    @Override
    public void handleCacheGetError(RuntimeException ex, Cache cache, Object key) {
        log.warn("Falha ao ler o cache {} chave {}: {}", cache.getName(), key, ex.getMessage());
    }

    @Override
    public void handleCachePutError(RuntimeException ex, Cache cache, Object key, Object value) {
        log.warn("Falha ao gravar o cache {} chave {}: {}", cache.getName(), key, ex.getMessage());
    }

    @Override
    public void handleCacheEvictError(RuntimeException ex, Cache cache, Object key) {
        log.warn("Falha ao invalidar o cache {} chave {} (valor antigo pode durar até o TTL): {}",
            cache.getName(), key, ex.getMessage());
    }

    @Override
    public void handleCacheClearError(RuntimeException ex, Cache cache) {
        log.warn("Falha ao limpar o cache {}: {}", cache.getName(), ex.getMessage());
    }
}
