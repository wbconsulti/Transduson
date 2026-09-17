"""
Camada de acesso ao HANA. Só é importada/usada quando config.USE_FIXTURES
for False.

Duas estratégias de acordo com a natureza do objeto de origem:

1) Resumo/Detalhe -> table functions reais no HANA
   (TF_FLUXO_CAIXA_RESUMIDO_DIARIO / TF_FLUXO_CAIXA_DETALHADO_DIARIO),
   chamadas com bind real via `?` (sem concatenar string nenhuma).

2) Pagar/Receber -> não são views nem table functions, são os scripts SQL
   completos do SAP B1 Query Manager (ver sql/pagar_v12.sql e
   sql/receber_v1.sql), que usam a sintaxe própria do Query Manager
   (`DECLARE`, `:pDataIni` etc.) - não dá pra rodar isso direto via hdbcli
   como um SELECT parametrizado comum. Por isso:
     - guardamos o texto original (íntegro) em sql/*.sql, só como
       referência/auditoria;
     - em runtime, extraímos a partir do primeiro `WITH` (descartando o
       preâmbulo `DECLARE`/atribuição, que é só o mecanismo de
       substituição de parâmetro do Query Manager) e substituímos
       `:pDataIni` / `:pDataFim` / `:pDataCorte` por literais de data já
       validados como `datetime.date` (nunca por texto vindo direto do
       usuário) - ver `_inject_date_params`.
     - as colunas que voltam têm nomes "humanos" (com espaço/acento) e um
       campo `_ord` (1 = total geral, 0 = detalhe); mapeamos tudo pros
       nomes da fixture em `_remap_rows`.
"""
import re
from contextlib import contextmanager
from datetime import date
from pathlib import Path

import config

SQL_DIR = Path(__file__).resolve().parent / "sql"


class HanaNotConfiguredError(RuntimeError):
    pass


def _require_hdbcli():
    try:
        from hdbcli import dbapi
        return dbapi
    except ImportError as exc:
        raise HanaNotConfiguredError(
            "Pacote 'hdbcli' não instalado. Rode: pip install -r requirements-hana.txt"
        ) from exc


@contextmanager
def get_connection():
    dbapi = _require_hdbcli()

    if not (config.HANA_HOST and config.HANA_USER and config.HANA_PASSWORD):
        raise HanaNotConfiguredError(
            "HANA_HOST / HANA_USER / HANA_PASSWORD não configurados no .env"
        )

    conn = dbapi.connect(
        address=config.HANA_HOST,
        port=config.HANA_PORT,
        user=config.HANA_USER,
        password=config.HANA_PASSWORD,
        encrypt=config.HANA_ENCRYPT,
        sslValidateCertificate=config.HANA_ENCRYPT,
    )
    try:
        if config.HANA_SCHEMA:
            cur = conn.cursor()
            cur.execute(f'SET SCHEMA "{config.HANA_SCHEMA}"')
            cur.close()
        yield conn
    finally:
        conn.close()


def _qualified(name: str) -> str:
    if config.HANA_SCHEMA:
        return f'"{config.HANA_SCHEMA}"."{name}"'
    return f'"{name}"'


def _rows_as_dicts(cursor) -> list[dict]:
    columns = [c[0] for c in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


# ---------------------------------------------------------------------------
# 1) Fluxo de Caixa - Resumo / Detalhe (table functions reais, bind real)
# ---------------------------------------------------------------------------

_SQL_RESUMO = """
SELECT
    F0."TipoLinha",
    F0."DataFluxo",
    F0."Banco",
    F0."ContaBanco",
    F0."UltimaDataMovimento",
    F0."DisponibilidadeAnterior",
    F0."RecebRealizado",
    F0."PedVenda",
    F0."NFReceber",
    F0."CartaoCredito",
    F0."TotalReceber",
    F0."PagtoRealizado",
    F0."PedCompra",
    F0."NFPagar",
    F0."TotalPagar",
    F0."ResultadoDia",
    F0."DisponibilidadeProjetada"
FROM {view}(?, ?) F0
ORDER BY
    F0."OrdemSecao",
    F0."DataFluxo",
    F0."Banco"
"""

# A function de detalhe devolve, no mesmo SELECT F0.*, vários "TipoLinha"
# diferentes (SALDO POR BANCO, TOTAL DOS BANCOS, linhas em branco
# separadoras, DETALHE DO DIA, TOTAL DO DIA, RESUMO GERAL DO PERÍODO) -
# tudo pensado pra impressão em Crystal Reports. Pra v1 do painel, só nos
# interessa o movimento em si: filtramos TipoLinha = 'DETALHE DO DIA'.
_SQL_DETALHE = """
SELECT
    F0."DataFluxo",
    F0."GrupoMovimento",
    F0."Natureza",
    F0."Origem",
    F0."Descricao",
    F0."Parceiro",
    F0."NumeroDocumento" AS "DocSAP",
    F0."Parcela",
    F0."Receber",
    F0."Pagar",
    F0."NomeCFO",
    F0."NomeCCusto",
    F0."Observacao"
FROM {view}(?, ?) F0
WHERE F0."TipoLinha" = 'DETALHE DO DIA'
ORDER BY
    F0."DataFluxo",
    F0."OrdemGrupo",
    F0."OrdemOrigem",
    F0."Parceiro",
    F0."NumeroDocumento",
    F0."Parcela",
    F0."Linha"
"""

# Última conciliação (SAP B1: OITR = Reconciliação Interna, cabeçalho;
# ITR1 = linhas). "Account" fica em ITR1, não em OITR - confirmado direto
# no HANA (TABLE_COLUMNS) em 2026-09-16. Junta pelas ReconNum e ignora
# conciliações canceladas.
_SQL_ULTIMA_CONCILIACAO = """
SELECT I."Account", MAX(H."ReconDate") AS "UltimaConciliacao"
FROM {itr1} I
INNER JOIN {oitr} H ON H."ReconNum" = I."ReconNum"
WHERE H."Canceled" = 'N'
  AND I."Account" IN ({placeholders})
GROUP BY I."Account"
"""


def _fetch_ultima_conciliacao(conn, contas: list[str]) -> dict:
    contas = [c for c in dict.fromkeys(contas) if c]  # únicos, preserva ordem, sem None/vazio
    if not contas:
        return {}
    placeholders = ", ".join(["?"] * len(contas))
    sql = _SQL_ULTIMA_CONCILIACAO.format(
        itr1=_qualified("ITR1"), oitr=_qualified("OITR"), placeholders=placeholders
    )
    cursor = conn.cursor()
    cursor.execute(sql, tuple(contas))
    resultado = {row[0]: row[1] for row in cursor.fetchall()}
    cursor.close()
    return resultado


def fetch_fluxo_resumo(data_ini: date, data_fim: date) -> list[dict]:
    sql = _SQL_RESUMO.format(view=_qualified(config.HANA_TF_FLUXO_RESUMO))
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql, (data_ini, data_fim))
        rows = _rows_as_dicts(cursor)
        cursor.close()

        contas_banco = [r["ContaBanco"] for r in rows if r.get("TipoLinha") == "SALDO POR BANCO"]
        conciliacoes = _fetch_ultima_conciliacao(conn, contas_banco)

    for row in rows:
        conta = row.pop("ContaBanco", None)
        row["UltimaConciliacao"] = conciliacoes.get(conta) if conta else None
    return rows


def fetch_fluxo_detalhe(data_ini: date, data_fim: date) -> list[dict]:
    sql = _SQL_DETALHE.format(view=_qualified(config.HANA_TF_FLUXO_DETALHE))
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql, (data_ini, data_fim))
        rows = _rows_as_dicts(cursor)
        cursor.close()
    return rows


# ---------------------------------------------------------------------------
# 2) Contas a Pagar / Receber (scripts do Query Manager)
# ---------------------------------------------------------------------------

_PARAM_TOKEN = re.compile(r":(pDataIni|pDataFim|pDataCorte)\b")


def _load_query_body(filename: str) -> str:
    """
    Lê sql/<filename> e devolve só a parte executável (a partir do primeiro
    `WITH` de alto nível), descartando o preâmbulo DECLARE/atribuição que é
    específico do SAP B1 Query Manager.
    """
    text = (SQL_DIR / filename).read_text(encoding="utf-8")
    match = re.search(r"\bWITH\b", text, re.IGNORECASE)
    if not match:
        raise RuntimeError(f"Não encontrei 'WITH' em {filename} - arquivo mudou de formato?")
    return text[match.start():]


def _inject_date_params(sql_text: str, *, pDataIni: date, pDataFim: date, pDataCorte: date) -> str:
    """
    Substitui :pDataIni / :pDataFim / :pDataCorte por literais de data.
    Só aceita datetime.date de verdade (nunca string crua) - isso é o que
    torna essa substituição segura mesmo não sendo bind real.
    """
    valores = {"pDataIni": pDataIni, "pDataFim": pDataFim, "pDataCorte": pDataCorte}
    for nome, valor in valores.items():
        if not isinstance(valor, date):
            raise TypeError(f"{nome} precisa ser datetime.date, veio {type(valor)}")

    def _sub(m):
        return f"'{valores[m.group(1)].isoformat()}'"

    return _PARAM_TOKEN.sub(_sub, sql_text)


# Nome real da coluna no resultado da query -> nome usado na fixture da v1.
# "_ord" é tratado à parte (vira TipoLinha).
_COLUMN_MAP_PAGAR = {
    "Ano": "Ano", "MesNum": "MesNum", "Vencimento": "Vencimento",
    "Status Previsão": "StatusPrevisao", "Cod.Fornec": "CodFornec",
    "Nome Fornec": "NomeFornec", "Valor Ano": "ValorAno", "Valor Mes": "ValorMes",
    "Valor Variavel": "ValorVariavel", "ImpRet": "ImpRet",
    "Lancado (NF)": "LancadoNF", "A PAGAR": "APagar", "Pago": "Pago",
    "Data Pagto": "DataPagto", "Parcela": "Parcela", "Var Realiz": "VarRealiz",
    "CFO": "CFO", "Nome CFO": "NomeCFO", "Tipo CFO": "TipoCFO",
    "Raiz CFO": "RaizCFO", "CCusto": "CCusto", "Nome CCusto": "NomeCCusto",
    "Centro Custo": "CentroCusto", "Class.Financ.": "ClassFinanc",
    "ContaPagamento": "ContaPagamento", "Comments": "Comments",
}

_COLUMN_MAP_RECEBER = {
    "Ano": "Ano", "MesNum": "MesNum", "Vencimento": "Vencimento",
    "Status Previsão": "StatusPrevisao", "Cod.Cliente": "CodCliente",
    "Nome Cliente": "NomeCliente", "Valor Ano": "ValorAno", "Valor Mes": "ValorMes",
    "Valor Variavel": "ValorVariavel", "ImpRet": "ImpRet",
    "Lancado (NF)": "LancadoNF", "A RECEBER": "AReceber", "Recebido": "Recebido",
    "Data Receb.": "DataReceb", "Parcela": "Parcela", "Var Realiz": "VarRealiz",
    "CFO": "CFO", "Nome CFO": "NomeCFO", "Tipo CFO": "TipoCFO",
    "Raiz CFO": "RaizCFO", "CCusto": "CCusto", "Nome CCusto": "NomeCCusto",
    "Centro Custo": "CentroCusto", "Class.Financ.": "ClassFinanc",
    "ContaRecebimento": "ContaRecebimento", "Comments": "Comments",
}


def _remap_rows(rows: list[dict], column_map: dict) -> list[dict]:
    out = []
    for row in rows:
        ord_val = row.get("_ord")
        novo = {"TipoLinha": "TOTAL GERAL" if ord_val == 1 else "DETALHE"}
        for col_real, col_alvo in column_map.items():
            novo[col_alvo] = row.get(col_real)
        out.append(novo)
    return out


def fetch_pagar(data_ini: date, data_fim: date, data_corte: date) -> list[dict]:
    corpo = _load_query_body("pagar_v12.sql")
    sql = _inject_date_params(corpo, pDataIni=data_ini, pDataFim=data_fim, pDataCorte=data_corte)
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql)
        rows = _rows_as_dicts(cursor)
        cursor.close()
    return _remap_rows(rows, _COLUMN_MAP_PAGAR)


def fetch_receber(data_ini: date, data_fim: date, data_corte: date) -> list[dict]:
    corpo = _load_query_body("receber_v1.sql")
    sql = _inject_date_params(corpo, pDataIni=data_ini, pDataFim=data_fim, pDataCorte=data_corte)
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql)
        rows = _rows_as_dicts(cursor)
        cursor.close()
    return _remap_rows(rows, _COLUMN_MAP_RECEBER)


# ---------------------------------------------------------------------------
# 3) Resumos agrupados (Pagar/Receber por Status, Vencimento, CFO, Centro de
#    Custo...) - alimentam os painéis de dashboard na tela de Resumo diário.
#    Mesmo mecanismo de sql/*.sql + substituição de parâmetro dos itens
#    acima; pagar_agrupamentos_v1.sql é a query que o usuário já usa em
#    produção. receber_agrupamentos_v1.sql foi montada reaproveitando os
#    CTEs já validados de receber_v1.sql, com a mesma seção de agrupamento
#    da versão de pagar.
# ---------------------------------------------------------------------------

# "_ord" terminado em 9 é linha separadora visual (pro Crystal Reports) -
# não tem dado, só o texto "----- RESUMO: X -----". Descartamos.
_AGRUPAMENTO_PARA_CHAVE = {
    "Status Previsão": "porStatus",
    "Data Vencimento": "porVencimento",
    "Nome CFO": "porCFO",
    "Raiz CFO": "porRaizCFO",
    "Tipo CFO": "porTipoCFO",
    "Centro de Custo": "porCentroCusto",
}


def _resumo_agrupado(rows: list[dict], rotulo_col: str, pendente_col: str, realizado_col: str) -> dict:
    resultado = {
        "total": None,
        "porStatus": [], "porVencimento": [], "porCFO": [],
        "porRaizCFO": [], "porTipoCFO": [], "porCentroCusto": [],
    }
    for row in rows:
        if row.get("_ord") is None or row["_ord"] % 10 != 0:
            continue  # separador visual, sem dado
        item = {
            "Rotulo": row.get(rotulo_col),
            "ValorAno": row.get("Valor Ano"),
            "ValorMes": row.get("Valor Mes"),
            "ValorVariavel": row.get("Valor Variavel"),
            "LancadoNF": row.get("Lancado (NF)"),
            "Pendente": row.get(pendente_col),
            "Realizado": row.get(realizado_col),
            "VarRealiz": row.get("Var Realiz"),
        }
        if row["Agrupamento"] == "Geral":
            resultado["total"] = item
        else:
            chave = _AGRUPAMENTO_PARA_CHAVE.get(row["Agrupamento"])
            if chave:
                resultado[chave].append(item)
    return resultado


def fetch_pagar_resumo(data_ini: date, data_fim: date, data_corte: date) -> dict:
    corpo = _load_query_body("pagar_agrupamentos_v1.sql")
    sql = _inject_date_params(corpo, pDataIni=data_ini, pDataFim=data_fim, pDataCorte=data_corte)
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql)
        rows = _rows_as_dicts(cursor)
        cursor.close()
    return _resumo_agrupado(rows, "Nome Fornec", "A PAGAR", "Pago")


def fetch_receber_resumo(data_ini: date, data_fim: date, data_corte: date) -> dict:
    corpo = _load_query_body("receber_agrupamentos_v1.sql")
    sql = _inject_date_params(corpo, pDataIni=data_ini, pDataFim=data_fim, pDataCorte=data_corte)
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql)
        rows = _rows_as_dicts(cursor)
        cursor.close()
    return _resumo_agrupado(rows, "Nome Cliente", "A RECEBER", "Recebido")


# ---------------------------------------------------------------------------
# 4) Histórico - comparação entre períodos (mês atual x mês anterior),
#    até o nível de fornecedor/cliente. Alimenta a tela "Histórico", pensada
#    pra leitura de diretoria (evolução, não só posição do momento).
#
#    Reaproveita fetch_pagar/fetch_receber/fetch_fluxo_resumo já validados -
#    roda cada um duas vezes (período atual e período anterior) e compara em
#    Python. Não inventa SQL novo pra isso.
# ---------------------------------------------------------------------------

def _aggregate_by_name(rows: list[dict], name_key: str, value_key: str, pending_key: str) -> dict:
    out = {}
    for r in rows:
        if r.get("TipoLinha") != "DETALHE":
            continue
        nome = r.get(name_key)
        if not nome:
            continue
        g = out.setdefault(nome, {"valor": 0.0, "pendente": 0.0})
        # hdbcli devolve DECIMAL como decimal.Decimal, não float - converte
        # explicitamente antes de somar (Python não mistura float+Decimal).
        g["valor"] += float(r.get(value_key) or 0)
        g["pendente"] += float(r.get(pending_key) or 0)
    return out


def _comparar_por_nome(rows_atual, rows_anterior, name_key, value_key, pending_key, top_n=10) -> dict:
    atual = _aggregate_by_name(rows_atual, name_key, value_key, pending_key)
    anterior = _aggregate_by_name(rows_anterior, name_key, value_key, pending_key)
    nomes = set(atual) | set(anterior)

    itens = []
    for nome in nomes:
        a = atual.get(nome, {"valor": 0.0, "pendente": 0.0})
        p = anterior.get(nome, {"valor": 0.0, "pendente": 0.0})
        variacao = a["valor"] - p["valor"]
        pct = (variacao / p["valor"] * 100) if p["valor"] else (100.0 if a["valor"] else 0.0)
        itens.append({
            "nome": nome,
            "atual": round(a["valor"], 2),
            "anterior": round(p["valor"], 2),
            "variacao": round(variacao, 2),
            "variacaoPct": round(pct, 1),
            "pendente": round(a["pendente"], 2),
        })
    itens.sort(key=lambda x: abs(x["variacao"]), reverse=True)

    total_atual = round(sum(v["valor"] for v in atual.values()), 2)
    total_anterior = round(sum(v["valor"] for v in anterior.values()), 2)
    variacao_total = round(total_atual - total_anterior, 2)
    pct_total = (variacao_total / total_anterior * 100) if total_anterior else (100.0 if total_atual else 0.0)

    return {
        "totalAtual": total_atual,
        "totalAnterior": total_anterior,
        "variacao": variacao_total,
        "variacaoPct": round(pct_total, 1),
        "itens": itens[:top_n],
    }


def fetch_pagar_comparativo(atual_ini, atual_fim, anterior_ini, anterior_fim, corte_atual, corte_anterior) -> dict:
    rows_atual = fetch_pagar(atual_ini, atual_fim, corte_atual)
    rows_anterior = fetch_pagar(anterior_ini, anterior_fim, corte_anterior)
    return _comparar_por_nome(rows_atual, rows_anterior, "NomeFornec", "ValorMes", "APagar")


def fetch_receber_comparativo(atual_ini, atual_fim, anterior_ini, anterior_fim, corte_atual, corte_anterior) -> dict:
    rows_atual = fetch_receber(atual_ini, atual_fim, corte_atual)
    rows_anterior = fetch_receber(anterior_ini, anterior_fim, corte_anterior)
    return _comparar_por_nome(rows_atual, rows_anterior, "NomeCliente", "ValorMes", "AReceber")


def fetch_disponibilidade_comparativa(atual_ini, atual_fim, anterior_ini, anterior_fim) -> dict:
    atual = fetch_fluxo_resumo(atual_ini, atual_fim)
    anterior = fetch_fluxo_resumo(anterior_ini, anterior_fim)
    serie_atual = [float(r["DisponibilidadeProjetada"]) for r in atual if r["TipoLinha"] == "FLUXO DIÁRIO"]
    serie_anterior = [float(r["DisponibilidadeProjetada"]) for r in anterior if r["TipoLinha"] == "FLUXO DIÁRIO"]
    final_atual = serie_atual[-1] if serie_atual else None
    final_anterior = serie_anterior[-1] if serie_anterior else None
    variacao = (final_atual - final_anterior) if (final_atual is not None and final_anterior is not None) else None
    return {
        "serieAtual": serie_atual,
        "serieAnterior": serie_anterior,
        "finalAtual": final_atual,
        "finalAnterior": final_anterior,
        "variacao": variacao,
    }
