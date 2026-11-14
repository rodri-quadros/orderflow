// Cenário 2 — estratégias de persistência: GET /api/experimentos/pedidos/{ALVO}?limite={LIMITE}.
//   ALVO = lazy | eager | join-fetch | nativa; LIMITE padrão 20 (uma página típica de listagem).
// Com limite=1000 o LAZY faria ~1.937 SQLs por requisição e saturaria o pool de 10 conexões em qualquer
// nível; os números de 10/100/1000 da Etapa 6 continuam valendo para a análise isolada.
import http from 'k6/http';
import { BASE_URL, validarAlvo, verificar } from './lib/config.js';

export { options, handleSummary } from './lib/config.js';

const ALVO = validarAlvo(__ENV.ALVO || 'lazy', ['lazy', 'eager', 'join-fetch', 'nativa']);
const LIMITE = Number(__ENV.LIMITE || 20);

export default function () {
    verificar(http.get(`${BASE_URL}/api/experimentos/pedidos/${ALVO}?limite=${LIMITE}`));
}
