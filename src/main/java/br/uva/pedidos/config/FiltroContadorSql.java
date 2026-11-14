package br.uva.pedidos.config;

import java.io.IOException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;

// Expõe no header X-SQL-Count quantos SQLs a requisição executou. O corpo fica em buffer
// (ContentCachingResponseWrapper) porque o header só pode ser escrito antes do envio do corpo.
@Component
public class FiltroContadorSql extends OncePerRequestFilter {

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        ContentCachingResponseWrapper resposta = new ContentCachingResponseWrapper(response);
        ContadorSql.zerar();
        try {
            chain.doFilter(request, resposta);
            resposta.setHeader("X-SQL-Count", String.valueOf(ContadorSql.total()));
            resposta.copyBodyToResponse();
        } finally {
            ContadorSql.limpar();
        }
    }
}
