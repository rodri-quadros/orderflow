package br.uva.pedidos.config;

import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.CachingConfigurer;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.interceptor.CacheErrorHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.data.redis.cache.RedisCacheConfiguration;
import org.springframework.data.redis.cache.RedisCacheManager;
import org.springframework.data.redis.cache.RedisCacheWriter;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.serializer.JacksonJsonRedisSerializer;
import org.springframework.data.redis.serializer.RedisSerializationContext.SerializationPair;

import br.uva.pedidos.dto.ProdutoDTO;

// order = HIGHEST_PRECEDENCE: o proxy de cache fica por fora do @Transactional. Assim um HIT
// retorna sem abrir transação nem pegar conexão do pool, e o evict do PUT roda após o commit.
@Configuration
@EnableCaching(order = Ordered.HIGHEST_PRECEDENCE)
public class CacheConfig implements CachingConfigurer {

    @Bean
    public RedisCacheManager cacheManager(RedisConnectionFactory conexao,
                                          @Value("${CACHE_TTL_PRODUTOS:5m}") Duration ttlProdutos) {
        // Serializador tipado: só reconstrói ProdutoDTO. O genérico grava o nome da classe no valor e
        // permitiria, a quem escrever no Redis, forçar a desserialização de classes arbitrárias.
        RedisCacheConfiguration produtos = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(ttlProdutos)
            .disableCachingNullValues()
            .serializeValuesWith(SerializationPair.fromSerializer(new JacksonJsonRedisSerializer<>(ProdutoDTO.class)));

        // immediateWrites: nesta versão o put/evict é assíncrono por padrão. Síncrono garante que,
        // quando o PUT responde, a chave antiga já saiu do Redis (invalidação determinística).
        RedisCacheWriter escritor = RedisCacheWriter.create(conexao, config -> config.immediateWrites());

        return RedisCacheManager.builder(escritor)
            .withCacheConfiguration("produtos", produtos)
            .disableCreateOnMissingCache()
            // Evict/put só depois do commit: evita que o cache receba um valor de transação desfeita.
            .transactionAware()
            .enableStatistics()
            .build();
    }

    @Override
    public CacheErrorHandler errorHandler() {
        return new TratadorErroCache();
    }
}
