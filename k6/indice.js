// Cenário 3 — índices: GET /api/clientes/{id}/pedidos?page=0&size=20, sorteando entre os clientes 1 a 5
// (85 a 225 pedidos). Com o índice composto todos seguem o caminho Index Scan; o cliente 545 (9 pedidos)
// usa Bitmap Heap Scan mesmo com o índice e não mostraria a diferença (Etapa 7).
// O estado do índice (sem ou com idx_pedido_cliente_data) é preparado por scripts/rodar-cenarios.sh.
import http from 'k6/http';
import { BASE_URL, sortear, verificar } from './lib/config.js';

export { options, handleSummary } from './lib/config.js';

const CLIENTES = [1, 2, 3, 4, 5];

export default function () {
    const id = sortear(CLIENTES);
    verificar(http.get(`${BASE_URL}/api/clientes/${id}/pedidos?page=0&size=20`, { tags: { name: 'clientes/pedidos' } }));
}
