// Cenário 1 — cache: GET /api/produtos/{id}/{ALVO}, com o id sorteado entre os 901 produtos ativos.
//   ALVO = sem-cache | com-cache | com-cache-sync
// O estado do cache (vazio, cheio, TTL mínimo) é preparado por scripts/rodar-cenarios.sh.
import http from 'k6/http';
import { SharedArray } from 'k6/data';
import { BASE_URL, sortear, validarAlvo, verificar } from './lib/config.js';

export { options, handleSummary } from './lib/config.js';

const ALVO = validarAlvo(__ENV.ALVO || 'com-cache', ['sem-cache', 'com-cache', 'com-cache-sync']);

// Ids gerados por consulta à base determinística (db/init/03_dados.sql): só produtos existentes e ativos.
const PRODUTOS = new SharedArray('produtos', () => JSON.parse(open('./dados/produtos-ativos.json')));

export default function () {
    const id = sortear(PRODUTOS);
    // A tag name agrupa as URLs (um id diferente por requisição) numa única série de métricas.
    verificar(http.get(`${BASE_URL}/api/produtos/${id}/${ALVO}`, { tags: { name: `produtos/${ALVO}` } }));
}
