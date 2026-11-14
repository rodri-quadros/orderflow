#!/usr/bin/env python3
"""Consolida os resultados do k6 e gera tabelas e gráficos (Etapa 9).

Lê resultados/carga/<cenario>/<alvo>/vus<N>_rep<R>.json (+ _metricas.json e _amostras.csv), gerados por
scripts/rodar-cenarios.sh, e escreve:
  resultados/carga/resumo.csv  - por cenário x alvo x VUs: mediana das repetições, mínimo e máximo
  resultados/carga/resumo.md   - as mesmas tabelas, legíveis
  resultados/graficos/*.png    - p95 x VUs, throughput x VUs, cauda (média/p95/p99) a 100 VUs, erros x VUs
                                 (quando houver) e partida a frio do cache
Nenhum número é escrito à mão: tudo vem dos arquivos de resultado.

Uso: .venv/bin/python scripts/gerar_graficos.py [pasta_resultados] [pasta_graficos]
     (padrão: resultados/carga e resultados/graficos)
"""
import json
import re
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402

RAIZ = Path(__file__).resolve().parent.parent
CARGA = Path(sys.argv[1]) if len(sys.argv) > 1 else RAIZ / "resultados" / "carga"
GRAFICOS = Path(sys.argv[2]) if len(sys.argv) > 2 else RAIZ / "resultados" / "graficos"

# Paleta categórica de referência, em ordem fixa (validada: vizinhos com CVD ΔE >= 9,1 e visão normal
# >= 19,6). Três cores ficam abaixo de 3:1 no fundo claro: o alívio são os marcadores de formas
# diferentes, os rótulos diretos (até 4 séries) e a tabela resumo.md.
CORES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4"]
MARCADORES = ["o", "s", "^", "D", "v"]
FUNDO, TEXTO, TEXTO_SECUNDARIO, GRADE = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3de"

ALVOS = {
    "cache": ["sem-cache", "com-cache-hit", "com-cache-miss", "frio-com-cache", "frio-com-cache-sync"],
    "persistencia": ["lazy", "eager", "join-fetch", "nativa"],
    "indice": ["sem-indice", "com-indice"],
}
ROTULOS = {
    "sem-cache": "Sem cache",
    "com-cache-hit": "Com cache, HIT",
    "com-cache-miss": "Com cache, MISS contínuo",
    "frio-com-cache": "Partida a frio",
    "frio-com-cache-sync": "Partida a frio, sync",
    "lazy": "LAZY",
    "eager": "EAGER",
    "join-fetch": "JOIN FETCH",
    "nativa": "SQL nativo",
    "sem-indice": "Sem índice",
    "com-indice": "Com índice composto",
}
TITULOS = {
    "cache": "Cenário 1 — cache",
    "persistencia": "Cenário 2 — persistência (limite=20)",
    "indice": "Cenário 3 — índice",
}
METRICAS = [
    "media_ms", "mediana_ms", "p95_ms", "p99_ms", "max_ms", "throughput", "erros_pct", "requisicoes",
    "api_cpu_media", "api_cpu_pico", "postgres_cpu_media", "postgres_cpu_pico", "k6_cpu_media",
    "redis_cpu_media", "jvm_mem_max_mb", "hikari_ativas_max", "hikari_pendentes_max",
    "taxa_hit_pct", "cache_miss", "miss_redundantes", "transacoes_por_requisicao", "blocos_por_transacao", "tuplas_por_transacao",
    "idx_scan_por_requisicao",
]
NIVEL_CAUDA = 100


def cor(cenario, alvo):
    return CORES[ALVOS[cenario].index(alvo)]


def marcador(cenario, alvo):
    return MARCADORES[ALVOS[cenario].index(alvo)]


def dividir(a, b):
    return a / b if b else float("nan")


def ler_rodada(arquivo):
    cenario, alvo = arquivo.parent.parent.name, arquivo.parent.name
    vus, rep = map(int, re.match(r"vus(\d+)_rep(\d+)", arquivo.stem).groups())
    k6 = json.loads(arquivo.read_text())
    metricas = json.loads(arquivo.with_name(f"{arquivo.stem}_metricas.json").read_text())
    # A última amostra cobre o encerramento do k6 (carga já parando): fica de fora das médias.
    amostras = pd.read_csv(arquivo.with_name(f"{arquivo.stem}_amostras.csv")).iloc[:-1]

    duracao = k6["metrics"]["http_req_duration"]["values"]
    requisicoes = k6["metrics"]["http_reqs"]["values"]
    banco, cache = metricas["banco"], metricas["cache"]
    return {
        "cenario": cenario, "alvo": alvo, "vus": vus, "rep": rep,
        "media_ms": duracao["avg"], "mediana_ms": duracao["med"], "p95_ms": duracao["p(95)"],
        "p99_ms": duracao["p(99)"], "max_ms": duracao["max"],
        "throughput": requisicoes["rate"], "requisicoes": requisicoes["count"],
        "erros_pct": k6["metrics"]["http_req_failed"]["values"]["rate"] * 100,
        "api_cpu_media": amostras["api_cpu"].mean(), "api_cpu_pico": amostras["api_cpu"].max(),
        "postgres_cpu_media": amostras["postgres_cpu"].mean(), "postgres_cpu_pico": amostras["postgres_cpu"].max(),
        "k6_cpu_media": amostras["k6_cpu"].mean(), "redis_cpu_media": amostras["redis_cpu"].mean(),
        "jvm_mem_max_mb": amostras["jvm_mem_mb"].max(),
        "hikari_ativas_max": amostras["hikari_ativas"].max(),
        "hikari_pendentes_max": amostras["hikari_pendentes"].max(),
        "taxa_hit_pct": dividir(cache["hit"], cache["hit"] + cache["miss"]) * 100,
        "cache_miss": cache["miss"],
        # Na partida a frio o Redis começa vazio: cada MISS além do primeiro de cada chave é redundante.
        "miss_redundantes": cache["miss"] - metricas["redis_chaves"] if alvo.startswith("frio") else float("nan"),
        "transacoes_por_requisicao": dividir(banco["transacoes"], requisicoes["count"]),
        "blocos_por_transacao": dividir(banco["blks_hit"] + banco["blks_read"], banco["transacoes"]),
        "tuplas_por_transacao": dividir(banco["tup_returned"], banco["transacoes"]),
        "idx_scan_por_requisicao": dividir(metricas["idx_scan"], requisicoes["count"]),
        "k6_status": metricas["k6_status"],
    }


def ler_rodadas():
    arquivos = [a for a in sorted(CARGA.glob("*/*/vus*_rep*.json")) if not a.stem.endswith("_metricas")]
    return pd.DataFrame([ler_rodada(a) for a in arquivos])


def resumir(rodadas):
    grupos = rodadas.groupby(["cenario", "alvo", "vus"])
    resumo = grupos[METRICAS].median()
    resumo = resumo.join(grupos[METRICAS].min().add_suffix("_min")).join(grupos[METRICAS].max().add_suffix("_max"))
    resumo.insert(0, "repeticoes", grupos.size())
    return resumo.reset_index()


# ---------- tabelas ----------

def numero(v, casas=1):
    return "—" if pd.isna(v) else f"{v:,.{casas}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def faixa(linha, metrica, casas=1):
    return f"{numero(linha[metrica], casas)} ({numero(linha[metrica + '_min'], casas)}–{numero(linha[metrica + '_max'], casas)})"


def tabela(cabecalho, linhas):
    saida = ["| " + " | ".join(cabecalho) + " |", "|" + "|".join("---" if i < 2 else "---:" for i in range(len(cabecalho))) + "|"]
    saida += ["| " + " | ".join(str(c) for c in linha) + " |" for linha in linhas]
    return "\n".join(saida)


def linhas_ordenadas(resumo, cenario):
    parte = resumo[resumo.cenario == cenario].copy()
    parte["ordem"] = parte.alvo.map(ALVOS[cenario].index)
    return parte.sort_values(["vus", "ordem"])


def pasta_relativa(pasta):
    try:
        return pasta.resolve().relative_to(RAIZ).as_posix()
    except ValueError:
        return pasta.as_posix()


def escrever_resumo_md(resumo, rodadas):
    minimo, maximo = int(resumo.repeticoes.min()), int(resumo.repeticoes.max())
    repeticoes = str(minimo) if minimo == maximo else f"{minimo} a {maximo}"
    texto = [
        "# Resumo dos testes de carga (k6)",
        "",
        f"Gerado por `scripts/gerar_graficos.py` a partir de `{pasta_relativa(CARGA)}/`. Cada valor é a **mediana das "
        f"repetições** ({repeticoes} por linha); entre parênteses, "
        "o mínimo e o máximo entre elas. Latências do `http_req_duration` do k6; throughput = requisições por segundo "
        "concluídas; CPU em % de um núcleo (100% = 1 núcleo inteiro; a máquina tem 12 lógicos). Os deltas do banco "
        "incluem a cauda do aquecimento do mesmo alvo (estatísticas publicadas com atraso), por isso são lidos como "
        "proporções (por transação, por requisição) e não em absoluto.",
        "",
    ]
    for cenario in ALVOS:
        parte = linhas_ordenadas(resumo, cenario)
        if parte.empty:
            continue
        texto += [f"## {TITULOS[cenario]}", "", "### Latência, throughput e erros", ""]
        texto.append(tabela(
            ["Alvo", "VUs", "Média (ms)", "p95 (ms)", "p99 (ms)", "Throughput (req/s)", "Erros (%)"],
            [[ROTULOS[l.alvo], l.vus, faixa(l, "media_ms", 2), faixa(l, "p95_ms", 2), faixa(l, "p99_ms", 2),
              faixa(l, "throughput", 0), faixa(l, "erros_pct", 2)] for _, l in parte.iterrows()]))
        texto += ["", "### Recursos (amostras a cada ~2 s durante a rodada)", ""]
        texto.append(tabela(
            ["Alvo", "VUs", "CPU API média / pico", "CPU PostgreSQL média / pico", "CPU k6 média",
             "Memória JVM máx (MB)", "Hikari ativas máx", "Hikari pendentes máx"],
            [[ROTULOS[l.alvo], l.vus, f"{numero(l.api_cpu_media, 0)} / {numero(l.api_cpu_pico, 0)}",
              f"{numero(l.postgres_cpu_media, 0)} / {numero(l.postgres_cpu_pico, 0)}", numero(l.k6_cpu_media, 0),
              numero(l.jvm_mem_max_mb, 0), numero(l.hikari_ativas_max, 0), numero(l.hikari_pendentes_max, 0)]
             for _, l in parte.iterrows()]))
        texto += ["", "### Banco e cache", ""]
        if cenario == "cache":
            texto.append(tabela(
                ["Alvo", "VUs", "Taxa de HIT (%)", "MISS na rodada", "MISS redundantes (frio)",
                 "Transações do banco por requisição"],
                [[ROTULOS[l.alvo], l.vus, numero(l.taxa_hit_pct, 1), numero(l.cache_miss, 0),
                  numero(l.miss_redundantes, 0), numero(l.transacoes_por_requisicao, 3)]
                 for _, l in parte.iterrows()]))
        else:
            colunas = ["Alvo", "VUs", "Blocos lidos por transação", "Tuplas lidas por transação"]
            if cenario == "indice":
                colunas.append("idx_scan por requisição")
            texto.append(tabela(colunas, [
                [ROTULOS[l.alvo], l.vus, numero(l.blocos_por_transacao, 1), numero(l.tuplas_por_transacao, 1)]
                + ([numero(l.idx_scan_por_requisicao, 2)] if cenario == "indice" else [])
                for _, l in parte.iterrows()]))
        texto.append("")
    falhas = rodadas[rodadas.k6_status != 0]
    texto += ["## Rodadas com falha do k6", "",
              "Nenhuma." if falhas.empty else ", ".join(f"{f.cenario}/{f.alvo} vus{f.vus} rep{f.rep}" for f in falhas.itertuples()),
              ""]
    (CARGA / "resumo.md").write_text("\n".join(texto), encoding="utf-8")


# ---------- gráficos ----------

def estilo():
    plt.rcParams.update({
        "figure.facecolor": FUNDO, "axes.facecolor": FUNDO, "savefig.facecolor": FUNDO,
        "axes.edgecolor": GRADE, "axes.labelcolor": TEXTO_SECUNDARIO, "axes.titlecolor": TEXTO,
        "xtick.color": TEXTO_SECUNDARIO, "ytick.color": TEXTO_SECUNDARIO, "text.color": TEXTO,
        "axes.grid": True, "grid.color": GRADE, "grid.linewidth": 0.8, "axes.axisbelow": True,
        "axes.spines.top": False, "axes.spines.right": False, "font.size": 10, "axes.titlesize": 12,
        "axes.titleweight": "bold", "legend.frameon": False, "figure.dpi": 150,
    })


def legenda_no_topo(ax):
    """Legenda numa faixa entre o título e os dados, para nunca cobrir uma série."""
    series = len(ax.get_legend_handles_labels()[0])
    ax.legend(loc="lower left", bbox_to_anchor=(0, 1.0), ncol=series, fontsize=9, borderaxespad=0.3)
    ax.set_title(ax.get_title(loc="left"), loc="left", pad=26)


def rotulos_diretos(ax, finais):
    """Rótulo no fim de cada linha (até 4 séries), afastando os que ficariam sobrepostos."""
    if len(finais) > 4:
        return
    y_min, y_max = ax.get_ylim()
    distancia = (y_max - y_min) * 0.06
    anterior = None
    for y, texto, x in sorted(finais):
        y = y if anterior is None else max(y, anterior + distancia)
        ax.annotate(texto, (x, y), xytext=(8, 0), textcoords="offset points", va="center",
                    fontsize=9, color=TEXTO_SECUNDARIO)
        anterior = y


def grafico_linhas(resumo, cenario, metrica, rotulo_y, arquivo, alvos=None):
    parte = resumo[resumo.cenario == cenario]
    niveis = sorted(parte.vus.unique())
    fig, ax = plt.subplots(figsize=(8, 4.6))
    finais = []
    for alvo in alvos or ALVOS[cenario]:
        serie = parte[parte.alvo == alvo].sort_values("vus")
        if serie.empty:
            continue
        x = [niveis.index(v) for v in serie.vus]
        erro = [serie[metrica] - serie[metrica + "_min"], serie[metrica + "_max"] - serie[metrica]]
        ax.errorbar(x, serie[metrica], yerr=erro, color=cor(cenario, alvo), marker=marcador(cenario, alvo),
                    markersize=7, linewidth=2, elinewidth=1, capsize=3, label=ROTULOS[alvo])
        finais.append((serie[metrica].iloc[-1], ROTULOS[alvo], x[-1]))
    ax.set_xticks(range(len(niveis)), [str(v) for v in niveis])
    ax.set_xlim(-0.3, len(niveis) - 1 + (0.9 if len(finais) <= 4 else 0.3))
    ax.set_ylim(bottom=0)
    ax.set_xlabel("Usuários virtuais simultâneos (VUs)")
    ax.set_ylabel(rotulo_y)
    ax.set_title(f"{TITULOS[cenario]}: {rotulo_y.split(' (')[0].lower()} por nível de carga", loc="left")
    legenda_no_topo(ax)
    rotulos_diretos(ax, finais)
    fig.text(0.01, 0.01, "Mediana de 3 repetições; barras = mínimo e máximo entre elas.", fontsize=8,
             color=TEXTO_SECUNDARIO)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(GRAFICOS / arquivo)
    plt.close(fig)


def grafico_cauda(resumo, cenario, arquivo):
    parte = resumo[(resumo.cenario == cenario) & (resumo.vus == NIVEL_CAUDA)]
    if parte.empty:
        return False
    alvos = [a for a in ALVOS[cenario] if a in set(parte.alvo)]
    metricas = [("media_ms", "Média"), ("p95_ms", "p95"), ("p99_ms", "p99")]
    largura = 0.8 / len(alvos)
    fig, ax = plt.subplots(figsize=(8, 4.6))
    for i, alvo in enumerate(alvos):
        linha = parte[parte.alvo == alvo].iloc[0]
        x = [j + (i - (len(alvos) - 1) / 2) * largura for j in range(len(metricas))]
        # Borda da cor do fundo: separa visualmente barras vizinhas (2 px).
        ax.bar(x, [linha[m] for m, _ in metricas], width=largura, color=cor(cenario, alvo),
               edgecolor=FUNDO, linewidth=2, label=ROTULOS[alvo])
    ax.set_xticks(range(len(metricas)), [nome for _, nome in metricas])
    ax.grid(axis="x", visible=False)
    ax.set_ylim(bottom=0)
    ax.set_ylabel("Latência (ms)")
    ax.set_title(f"{TITULOS[cenario]}: cauda da latência com {NIVEL_CAUDA} VUs", loc="left")
    legenda_no_topo(ax)
    fig.text(0.01, 0.01, "Mediana de 3 repetições. Melhorar a média não basta: compare p95 e p99.",
             fontsize=8, color=TEXTO_SECUNDARIO)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(GRAFICOS / arquivo)
    plt.close(fig)
    return True


def grafico_partida_frio(resumo, arquivo):
    parte = resumo[resumo.alvo.isin(["frio-com-cache", "frio-com-cache-sync"])]
    if parte.empty:
        return
    niveis = sorted(parte.vus.unique())
    alvos = ["frio-com-cache", "frio-com-cache-sync"]
    largura = 0.38
    fig, ax = plt.subplots(figsize=(8, 4.6))
    for i, alvo in enumerate(alvos):
        serie = parte[parte.alvo == alvo].set_index("vus").reindex(niveis)
        x = [j + (i - 0.5) * largura for j in range(len(niveis))]
        erro = [serie.miss_redundantes - serie.miss_redundantes_min, serie.miss_redundantes_max - serie.miss_redundantes]
        ax.bar(x, serie.miss_redundantes, width=largura, color=CORES[i], edgecolor=FUNDO, linewidth=2,
               yerr=erro, error_kw={"elinewidth": 1, "capsize": 3, "ecolor": TEXTO_SECUNDARIO},
               label="@Cacheable" if i == 0 else "@Cacheable(sync = true)")
    ax.set_xticks(range(len(niveis)), [str(v) for v in niveis])
    ax.set_ylim(bottom=0)
    ax.set_xlabel("Usuários virtuais simultâneos (VUs)")
    ax.set_ylabel("MISS redundantes (consultas ao banco)")
    ax.set_title("Cenário 1 — partida a frio: consultas repetidas da mesma chave", loc="left")
    legenda_no_topo(ax)
    fig.text(0.01, 0.01, "Redis vazio no início de cada rodada de 30 s. MISS redundantes = MISS − chaves criadas "
             "(901 produtos).\nMediana de 3 repetições; barras = mínimo e máximo entre elas.", fontsize=8,
             color=TEXTO_SECUNDARIO)
    ax.grid(axis="x", visible=False)
    fig.tight_layout(rect=(0, 0.05, 1, 1))
    fig.savefig(GRAFICOS / arquivo)
    plt.close(fig)


def gerar_graficos(resumo):
    GRAFICOS.mkdir(parents=True, exist_ok=True)
    estilo()
    gerados = []
    for cenario in ALVOS:
        if resumo[resumo.cenario == cenario].empty:
            continue
        # Partida a frio fica no gráfico próprio: os 30 s misturam a fase de MISS e a de HIT.
        alvos = [a for a in ALVOS[cenario] if not a.startswith("frio")]
        grafico_linhas(resumo, cenario, "p95_ms", "Latência p95 (ms)", f"{cenario}_p95.png", alvos)
        grafico_linhas(resumo, cenario, "throughput", "Throughput (req/s)", f"{cenario}_throughput.png", alvos)
        gerados += [f"{cenario}_p95.png", f"{cenario}_throughput.png"]
        if grafico_cauda(resumo[~resumo.alvo.str.startswith("frio")], cenario, f"{cenario}_cauda_{NIVEL_CAUDA}vus.png"):
            gerados.append(f"{cenario}_cauda_{NIVEL_CAUDA}vus.png")
        if resumo[resumo.cenario == cenario].erros_pct_max.gt(0).any():
            grafico_linhas(resumo, cenario, "erros_pct", "Taxa de erros (%)", f"{cenario}_erros.png")
            gerados.append(f"{cenario}_erros.png")
    if not resumo[resumo.alvo.str.startswith("frio")].empty:
        grafico_partida_frio(resumo, "cache_partida_frio.png")
        gerados.append("cache_partida_frio.png")
    return gerados


def main():
    rodadas = ler_rodadas()
    if rodadas.empty:
        raise SystemExit(f"Nenhum resultado em {CARGA}")
    resumo = resumir(rodadas)
    resumo.round(3).to_csv(CARGA / "resumo.csv", index=False)
    escrever_resumo_md(resumo, rodadas)
    gerados = gerar_graficos(resumo)
    print(f"{len(rodadas)} rodadas -> resumo.csv, resumo.md e {len(gerados)} gráficos: {', '.join(gerados)}")


if __name__ == "__main__":
    main()
