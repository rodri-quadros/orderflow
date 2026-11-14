"""Confere se cada número das tabelas do README existe nos arquivos de resultados/ (Etapa 10).

Uso: python3 scripts/conferir_numeros.py [--prosa] [README.md ...]   (--prosa confere também o texto corrido)
Os números do README estão no formato brasileiro (1.234,56). Um número confere quando algum valor dos
arquivos de origem, arredondado para as mesmas casas decimais, é igual a ele. Razões ("2,4×") e
percentuais derivados são listados à parte para conferência (são calculados a partir de dois valores de
origem); números de versão (4.1.2), códigos HTTP e portas são ignorados.
Termina com código 1 se algum número não conferir.
"""
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
FONTES = [p for p in (RAIZ / "resultados").rglob("*")
          if p.suffix in {".txt", ".csv", ".md"} and "_amostras" not in p.name]

CODIGOS_HTTP = {"200", "201", "400", "404", "409", "422", "500", "8080", "18080"}   # e portas
NUMERO = re.compile(r"(?<![\w.])\d[\d.,]*\d|(?<![\w.,])\d(?![\w])")


def valores_da_fonte(texto):
    """Cada número da fonte em duas leituras: inglês (1,234.56) e brasileiro (1.234,56)."""
    valores = set()
    for bruto in NUMERO.findall(texto.replace("..", " ")):   # custos dos planos: cost=0.42..707.79
        for milhar, decimal in ((",", "."), (".", ",")):
            candidato = bruto.replace(milhar, "").replace(decimal, ".")
            try:
                valores.add(float(candidato))
            except ValueError:
                pass
    return valores


def casas(numero_br):
    return len(numero_br.split(",")[1]) if "," in numero_br else 0


def confere(numero_br, fonte):
    valor = float(numero_br.replace(".", "").replace(",", "."))
    d = casas(numero_br)
    tolerancia = 0.5 * 10 ** -d + 1e-9
    return any(abs(v - valor) <= tolerancia for v in fonte)


def celulas(readme, prosa):
    """(linha, célula) de cada célula de tabela (e, com prosa, de cada linha de texto) fora de código."""
    em_codigo = False
    for n, linha in enumerate(readme.read_text().splitlines(), 1):
        if linha.startswith("```"):
            em_codigo = not em_codigo
            continue
        if em_codigo or set(linha) <= set("|-: "):
            continue
        if linha.startswith("|"):
            for celula in linha.strip("|").split("|"):
                yield n, celula.strip()
        elif prosa and not linha.startswith(("#", "![")):
            yield n, linha.strip()


def main():
    fonte = set()
    for arquivo in FONTES:
        fonte |= valores_da_fonte(arquivo.read_text(errors="ignore"))
    prosa = "--prosa" in sys.argv
    readmes = [Path(a) for a in sys.argv[1:] if a != "--prosa"] or [RAIZ / "README.md"]
    falhas = derivados = conferidos = 0
    for readme in readmes:
        for n, celula in celulas(readme, prosa):
            texto = re.sub(r"\]\([^)]*\)", "]", celula)              # ignora os caminhos dos links
            texto = re.sub(r"`[^`]*`", "", texto)                    # e identificadores de código
            for m in NUMERO.finditer(texto):
                numero = m.group()
                if re.fullmatch(r"\d+(\.\d+){2,}", numero) or numero in CODIGOS_HTTP:
                    continue
                depois = texto[m.end():m.end() + 7]
                if depois.startswith(("×", " vez")) or (depois.startswith("%") and not confere(numero, fonte)):
                    derivados += 1
                    print(f"  derivado  {readme.name}:{n}  {numero}{depois[:5]}  ({celula[:70]})")
                elif confere(numero, fonte):
                    conferidos += 1
                else:
                    falhas += 1
                    print(f"  [FALHA]   {readme.name}:{n}  {numero}  ({celula[:70]})")
    print(f"Números de tabela conferidos: {conferidos} | derivados (razões e percentuais): {derivados} | "
          f"sem origem: {falhas}")
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
