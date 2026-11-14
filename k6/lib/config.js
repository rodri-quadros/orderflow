// Configuração comum dos cenários de carga. Parâmetros por variável de ambiente:
//   BASE_URL (padrão http://localhost:18080), VUS (10), DURACAO (30s), SAIDA (arquivo JSON do resumo), ROTULO.
import { check } from 'k6';

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:18080';

// Modelo fechado: cada VU faz a próxima requisição assim que recebe a resposta anterior (sem think time).
// VUs não são requisições por segundo (enunciado 6.3); o throughput (http_reqs/s) é o resultado medido.
export const options = {
    scenarios: {
        carga: {
            executor: 'constant-vus',
            vus: Number(__ENV.VUS || 10),
            duration: __ENV.DURACAO || '30s',
            gracefulStop: '10s',
        },
    },
    summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
    // O corpo não é analisado; descartá-lo reduz o custo do próprio k6, que divide a máquina com a API.
    discardResponseBodies: true,
};

export function verificar(resposta) {
    check(resposta, { 'status 200': (r) => r.status === 200 });
}

export function sortear(lista) {
    return lista[Math.floor(Math.random() * lista.length)];
}

export function validarAlvo(alvo, permitidos) {
    if (!permitidos.includes(alvo)) {
        throw new Error(`ALVO inválido: ${alvo}. Use um de: ${permitidos.join(', ')}`);
    }
    return alvo;
}

// Grava o resumo completo em JSON (SAIDA) e imprime uma linha legível no console.
export function handleSummary(data) {
    const duracao = data.metrics.http_req_duration.values;
    const requisicoes = data.metrics.http_reqs.values;
    const falhas = data.metrics.http_req_failed.values.rate;
    const linha = `${__ENV.ROTULO || ''} VUs=${__ENV.VUS || 10} | ${requisicoes.count} req, `
        + `${requisicoes.rate.toFixed(1)} req/s | média ${duracao.avg.toFixed(2)} ms | `
        + `p95 ${duracao['p(95)'].toFixed(2)} ms | p99 ${duracao['p(99)'].toFixed(2)} ms | `
        + `erros ${(falhas * 100).toFixed(2)}%\n`;
    const saida = { stdout: linha };
    if (__ENV.SAIDA) {
        saida[__ENV.SAIDA] = JSON.stringify(data, null, 2);
    }
    return saida;
}
