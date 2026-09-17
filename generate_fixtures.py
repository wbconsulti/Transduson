"""
Gera as fixtures JSON demo para a v1 do painel Transduson.
Roda uma vez, grava em fixtures/*.json. Não é parte do app em runtime.
"""
import json
import random
from datetime import date, timedelta

random.seed(42)

OUT = "fixtures"

BANCOS = ["Bradesco CC", "Itaú CC", "Santander Aplicação"]

FORNECEDORES = [
    ("F001", "Fornecedor Demo A - Contrastes"),
    ("F002", "Fornecedor Demo B - Manutenção Equip."),
    ("F003", "Fornecedor Demo C - Insumos Lab."),
    ("F004", "Fornecedor Demo D - TI e Software"),
    ("F005", "Fornecedor Demo E - Limpeza"),
    ("F006", "Fornecedor Demo F - Energia Elétrica"),
    ("F007", "Fornecedor Demo G - Telecom"),
    ("F008", "Fornecedor Demo H - Consultoria Médica"),
    ("F009", "Fornecedor Demo I - Locação Imóvel"),
]

CLIENTES = [
    ("C001", "Cliente Demo A - Convênio Saúde Norte"),
    ("C002", "Cliente Demo B - Convênio Vida Plena"),
    ("C003", "Cliente Demo C - Convênio MedFácil"),
    ("C004", "Cliente Demo D - Particular Balcão"),
    ("C005", "Cliente Demo E - Convênio Bem Estar"),
    ("C006", "Cliente Demo F - Hospital Parceiro"),
    ("C007", "Cliente Demo G - Convênio Único"),
    ("C008", "Cliente Demo H - Clínica Parceira"),
    ("C009", "Cliente Demo I - Convênio Regional"),
]

CFOS = [
    ("3.01", "CFO Operacional - Insumos", "Operacional"),
    ("3.02", "CFO Operacional - Manutenção", "Operacional"),
    ("4.01", "CFO Administrativo - TI", "Administrativo"),
    ("4.02", "CFO Administrativo - Instalações", "Administrativo"),
    ("5.01", "CFO Receita - Convênios", "Receita"),
]

CCUSTOS = [
    ("CC01", "Diagnóstico por Imagem"),
    ("CC02", "Administrativo"),
    ("CC03", "Comercial"),
    ("CC04", "TI"),
]

GRUPOS_MOV = ["Título", "Cartão", "Pedido", "Transferência"]
NATUREZAS = ["Receita", "Despesa"]
ORIGENS = ["SAP", "Manual", "Convênio", "PDV"]
STATUS_PREV = ["Previsto", "Confirmado", "Vencido", "Pago"]
STATUS_PREV_RECEBER = ["Previsto", "Confirmado", "Vencido", "Recebido"]

START = date(2026, 8, 6)
N_DAYS = 30


def brl(v):
    return round(v, 2)


def daterange(n):
    return [START + timedelta(days=i) for i in range(n)]


# ---------------------------------------------------------------------------
# 1) Fluxo de Caixa - Resumo Diário
#
# Formato confirmado contra o HANA real (2026-09): NÃO é "uma linha por
# banco por dia" o tempo todo. É:
#   - "SALDO POR BANCO": posição de abertura de cada banco, só no dia
#     anterior ao início do período pedido.
#   - "TOTAL DOS BANCOS": soma dessas posições de abertura (1 linha).
#   - "FLUXO DIÁRIO": uma linha por dia dentro do período, Banco=null,
#     consolidada pra empresa toda - porque movimento futuro ainda não tem
#     banco definido no SAP (só se sabe que vai debitar/creditar).
# ---------------------------------------------------------------------------
resumo_rows = []
detalhe_rows = []
doc_counter = 1

opening_date = START - timedelta(days=1)
saldo_banco = {b: random.uniform(180_000, 420_000) for b in BANCOS}
total_abertura = 0.0

for banco in BANCOS:
    saldo = brl(saldo_banco[banco])
    total_abertura += saldo
    ultima_conciliacao = opening_date - timedelta(days=random.randint(0, 12))
    resumo_rows.append({
        "TipoLinha": "SALDO POR BANCO",
        "DataFluxo": opening_date.isoformat(),
        "Banco": banco,
        "UltimaDataMovimento": opening_date.isoformat(),
        "UltimaConciliacao": ultima_conciliacao.isoformat(),
        "DisponibilidadeAnterior": saldo,
        "RecebRealizado": 0, "PedVenda": 0, "NFReceber": 0, "CartaoCredito": 0,
        "TotalReceber": 0, "PagtoRealizado": 0, "PedCompra": 0, "NFPagar": 0,
        "TotalPagar": 0, "ResultadoDia": 0,
        "DisponibilidadeProjetada": None,
    })

total_abertura = brl(total_abertura)
resumo_rows.append({
    "TipoLinha": "TOTAL DOS BANCOS",
    "DataFluxo": opening_date.isoformat(),
    "Banco": "TOTAL DOS BANCOS",
    "UltimaDataMovimento": None,
    "UltimaConciliacao": None,
    "DisponibilidadeAnterior": total_abertura,
    "RecebRealizado": 0, "PedVenda": 0, "NFReceber": 0, "CartaoCredito": 0,
    "TotalReceber": 0, "PagtoRealizado": 0, "PedCompra": 0, "NFPagar": 0,
    "TotalPagar": 0, "ResultadoDia": 0,
    "DisponibilidadeProjetada": total_abertura,
})


def split(total, n):
    if n == 1 or total == 0:
        return [brl(total)]
    cuts = sorted(random.uniform(0.05, 0.95) for _ in range(n - 1))
    bounds = [0] + cuts + [1]
    return [brl(total * (bounds[i + 1] - bounds[i])) for i in range(n)]


saldo_consolidado = total_abertura

for d in daterange(N_DAYS):
    receb_realizado = brl(random.uniform(2_000, 18_000))
    ped_venda = brl(random.uniform(1_000, 9_000))
    nf_receber = brl(random.uniform(500, 6_000))
    cartao_credito = brl(random.uniform(1_500, 12_000))
    total_receber = brl(receb_realizado + ped_venda + nf_receber + cartao_credito)

    pagto_realizado = brl(random.uniform(1_500, 14_000))
    ped_compra = brl(random.uniform(500, 7_000))
    nf_pagar = brl(random.uniform(500, 5_000))
    total_pagar = brl(pagto_realizado + ped_compra + nf_pagar)

    resultado_dia = brl(total_receber - total_pagar)
    saldo_consolidado = brl(saldo_consolidado + resultado_dia)

    resumo_rows.append({
        "TipoLinha": "FLUXO DIÁRIO",
        "DataFluxo": d.isoformat(),
        "Banco": None,
        "UltimaDataMovimento": None,
        "UltimaConciliacao": None,
        "DisponibilidadeAnterior": 0,
        "RecebRealizado": receb_realizado,
        "PedVenda": ped_venda,
        "NFReceber": nf_receber,
        "CartaoCredito": cartao_credito,
        "TotalReceber": total_receber,
        "PagtoRealizado": pagto_realizado,
        "PedCompra": ped_compra,
        "NFPagar": nf_pagar,
        "TotalPagar": total_pagar,
        "ResultadoDia": resultado_dia,
        "DisponibilidadeProjetada": saldo_consolidado,
    })

    # ---- Fluxo de Caixa - Detalhe: quebra o dia em 2 a 4 movimentos de
    # recebimento e 2 a 4 de pagamento, cujo somatório bate exatamente com
    # TotalReceber / TotalPagar do resumo desse dia.
    n_receb = random.randint(2, 4)
    n_pagar = random.randint(2, 4)
    partes_receber = split(total_receber, n_receb)
    partes_pagar = split(total_pagar, n_pagar)

    saldo_anterior_dia = brl(saldo_consolidado - resultado_dia)
    saldo_corrente = saldo_anterior_dia
    movimentos = (
        [("Receita", v, True) for v in partes_receber]
        + [("Despesa", v, False) for v in partes_pagar]
    )
    random.shuffle(movimentos)

    for natureza, valor, is_receber in movimentos:
        cfo = random.choice(CFOS)
        ccusto = random.choice(CCUSTOS)
        receber_v = valor if is_receber else 0.0
        pagar_v = 0.0 if is_receber else valor
        resultado_mov = brl(receber_v - pagar_v)
        saldo_corrente = brl(saldo_corrente + resultado_mov)
        parceiro = random.choice(CLIENTES)[1] if is_receber else random.choice(FORNECEDORES)[1]
        detalhe_rows.append({
            "DataFluxo": d.isoformat(),
            "GrupoMovimento": random.choice(GRUPOS_MOV),
            "Natureza": natureza,
            "Origem": random.choice(ORIGENS),
            "Descricao": f"{'Recebimento' if is_receber else 'Pagamento'} - {parceiro}",
            "UltimaDataMovimento": d.isoformat(),
            "Parceiro": parceiro,
            "DocSAP": f"DOC{100000 + doc_counter}",
            "Parcela": f"{random.randint(1,3)}/{random.randint(1,3)}",
            "SaldoAnterior": brl(saldo_corrente - resultado_mov),
            "Receber": brl(receber_v),
            "Pagar": brl(pagar_v),
            "ResultadoDia": resultado_mov,
            "SaldoProjetado": saldo_corrente,
            "NomeCFO": cfo[1],
            "NomeCCusto": ccusto[1],
            "Observacao": "" if random.random() > 0.15 else "Confirmar com controladoria",
        })
        doc_counter += 1

# ---------------------------------------------------------------------------
# 2) Contas a Pagar
# ---------------------------------------------------------------------------
pagar_rows = []
total_geral = {
    "ValorAno": 0.0, "ValorMes": 0.0, "ValorVariavel": 0.0, "ImpRet": 0.0,
    "LancadoNF": 0.0, "APagar": 0.0, "Pago": 0.0,
}
N_PAGAR = 52
for i in range(N_PAGAR):
    fornec = random.choice(FORNECEDORES)
    cfo = random.choice(CFOS)
    ccusto = random.choice(CCUSTOS)
    ano, mes = 2026, random.randint(7, 10)
    venc = date(ano, min(mes, 12), random.randint(1, 28))
    status = random.choice(STATUS_PREV)
    valor_mes = brl(random.uniform(800, 22_000))
    valor_variavel = brl(valor_mes * random.uniform(0, 0.2))
    valor_ano = brl(valor_mes * random.uniform(10, 13))
    imp_ret = brl(valor_mes * random.uniform(0, 0.05))
    lancado_nf = brl(valor_mes * random.uniform(0.8, 1.0))
    pago = valor_mes if status == "Pago" else 0.0
    a_pagar = brl(valor_mes - pago)
    data_pagto = venc.isoformat() if status == "Pago" else None

    row = {
        "Ano": ano, "MesNum": mes, "Vencimento": venc.isoformat(),
        "StatusPrevisao": status, "CodFornec": fornec[0], "NomeFornec": fornec[1],
        "ValorAno": valor_ano, "ValorMes": valor_mes, "ValorVariavel": valor_variavel,
        "ImpRet": imp_ret, "LancadoNF": lancado_nf, "APagar": a_pagar, "Pago": brl(pago),
        "DataPagto": data_pagto, "Parcela": f"{random.randint(1,3)}/{random.randint(1,3)}",
        "VarRealiz": brl(valor_mes - lancado_nf), "CFO": cfo[0], "NomeCFO": cfo[1],
        "TipoCFO": cfo[2], "RaizCFO": cfo[0].split(".")[0], "CCusto": ccusto[0],
        "NomeCCusto": ccusto[1], "CentroCusto": ccusto[0], "ClassFinanc": "Operacional" if cfo[2] == "Operacional" else "Administrativo",
        "ContaPagamento": random.choice(BANCOS), "Comments": "",
    }
    pagar_rows.append(row)
    for k in total_geral:
        total_geral[k] += row[k]

pagar_out = [{
    "TipoLinha": "TOTAL GERAL", "Ano": None, "MesNum": None, "Vencimento": None,
    "StatusPrevisao": None, "CodFornec": None, "NomeFornec": "TOTAL GERAL",
    **{k: brl(v) for k, v in total_geral.items()},
    "DataPagto": None, "Parcela": None, "VarRealiz": brl(total_geral["ValorMes"] - total_geral["LancadoNF"]),
    "CFO": None, "NomeCFO": None, "TipoCFO": None, "RaizCFO": None, "CCusto": None,
    "NomeCCusto": None, "CentroCusto": None, "ClassFinanc": None, "ContaPagamento": None,
    "Comments": "",
}] + [{"TipoLinha": "DETALHE", **r} for r in pagar_rows]

# ---------------------------------------------------------------------------
# 3) Contas a Receber (espelho do Pagar)
# ---------------------------------------------------------------------------
receber_rows = []
total_geral_r = {
    "ValorAno": 0.0, "ValorMes": 0.0, "ValorVariavel": 0.0, "ImpRet": 0.0,
    "LancadoNF": 0.0, "AReceber": 0.0, "Recebido": 0.0,
}
N_RECEBER = 55
for i in range(N_RECEBER):
    cliente = random.choice(CLIENTES)
    cfo = CFOS[-1]  # receita
    ccusto = random.choice(CCUSTOS)
    ano, mes = 2026, random.randint(7, 10)
    venc = date(ano, min(mes, 12), random.randint(1, 28))
    status = random.choice(STATUS_PREV_RECEBER)
    valor_mes = brl(random.uniform(600, 15_000))
    valor_variavel = brl(valor_mes * random.uniform(0, 0.15))
    valor_ano = brl(valor_mes * random.uniform(10, 13))
    imp_ret = brl(valor_mes * random.uniform(0, 0.03))
    lancado_nf = brl(valor_mes * random.uniform(0.85, 1.0))
    recebido = valor_mes if status == "Recebido" else 0.0
    a_receber = brl(valor_mes - recebido)
    data_receb = venc.isoformat() if status == "Recebido" else None

    row = {
        "Ano": ano, "MesNum": mes, "Vencimento": venc.isoformat(),
        "StatusPrevisao": status, "CodCliente": cliente[0], "NomeCliente": cliente[1],
        "ValorAno": valor_ano, "ValorMes": valor_mes, "ValorVariavel": valor_variavel,
        "ImpRet": imp_ret, "LancadoNF": lancado_nf, "AReceber": a_receber, "Recebido": brl(recebido),
        "DataReceb": data_receb, "Parcela": f"{random.randint(1,3)}/{random.randint(1,3)}",
        "VarRealiz": brl(valor_mes - lancado_nf), "CFO": cfo[0], "NomeCFO": cfo[1],
        "TipoCFO": cfo[2], "RaizCFO": cfo[0].split(".")[0], "CCusto": ccusto[0],
        "NomeCCusto": ccusto[1], "CentroCusto": ccusto[0], "ClassFinanc": "Receita",
        "ContaRecebimento": random.choice(BANCOS), "Comments": "",
    }
    receber_rows.append(row)
    for k in total_geral_r:
        total_geral_r[k] += row[k]

receber_out = [{
    "TipoLinha": "TOTAL GERAL", "Ano": None, "MesNum": None, "Vencimento": None,
    "StatusPrevisao": None, "CodCliente": None, "NomeCliente": "TOTAL GERAL",
    **{k: brl(v) for k, v in total_geral_r.items()},
    "DataReceb": None, "Parcela": None, "VarRealiz": brl(total_geral_r["ValorMes"] - total_geral_r["LancadoNF"]),
    "CFO": None, "NomeCFO": None, "TipoCFO": None, "RaizCFO": None, "CCusto": None,
    "NomeCCusto": None, "CentroCusto": None, "ClassFinanc": None, "ContaRecebimento": None,
    "Comments": "",
}] + [{"TipoLinha": "DETALHE", **r} for r in receber_rows]


# ---------------------------------------------------------------------------
# Resumos agrupados (Pagar/Receber por Status, Vencimento, CFO, Centro de
# Custo...) - mesmo formato que db.py._resumo_agrupado produz a partir do
# HANA real, pra alimentar os mesmos painéis de dashboard em modo demo.
# ---------------------------------------------------------------------------

def _agrupar(rows, chave, rotulo_key, pendente_key, realizado_key):
    grupos = {}
    for r in rows:
        rotulo = r.get(rotulo_key)
        rotulo = rotulo.isoformat() if hasattr(rotulo, "isoformat") else rotulo
        g = grupos.setdefault(rotulo, {
            "Rotulo": rotulo, "ValorAno": 0.0, "ValorMes": 0.0, "ValorVariavel": 0.0,
            "LancadoNF": 0.0, "Pendente": 0.0, "Realizado": 0.0, "VarRealiz": 0.0,
        })
        g["ValorAno"] += r["ValorAno"]
        g["ValorMes"] += r["ValorMes"]
        g["ValorVariavel"] += r["ValorVariavel"]
        g["LancadoNF"] += r["LancadoNF"]
        g["Pendente"] += r[pendente_key]
        g["Realizado"] += r[realizado_key]
        g["VarRealiz"] += r["VarRealiz"]
    return [{k: (brl(v) if isinstance(v, float) else v) for k, v in g.items()} for g in grupos.values()]


def _resumo_agrupado_fixture(rows, rotulo_geral, pendente_key, realizado_key):
    total = {
        "Rotulo": rotulo_geral, "ValorAno": 0.0, "ValorMes": 0.0, "ValorVariavel": 0.0,
        "LancadoNF": 0.0, "Pendente": 0.0, "Realizado": 0.0, "VarRealiz": 0.0,
    }
    for r in rows:
        total["ValorAno"] += r["ValorAno"]
        total["ValorMes"] += r["ValorMes"]
        total["ValorVariavel"] += r["ValorVariavel"]
        total["LancadoNF"] += r["LancadoNF"]
        total["Pendente"] += r[pendente_key]
        total["Realizado"] += r[realizado_key]
        total["VarRealiz"] += r["VarRealiz"]
    total = {k: (brl(v) if isinstance(v, float) else v) for k, v in total.items()}

    return {
        "total": total,
        "porStatus": _agrupar(rows, "porStatus", "StatusPrevisao", pendente_key, realizado_key),
        "porVencimento": _agrupar(rows, "porVencimento", "Vencimento", pendente_key, realizado_key),
        "porCFO": _agrupar(rows, "porCFO", "NomeCFO", pendente_key, realizado_key),
        "porRaizCFO": _agrupar(rows, "porRaizCFO", "RaizCFO", pendente_key, realizado_key),
        "porTipoCFO": _agrupar(rows, "porTipoCFO", "TipoCFO", pendente_key, realizado_key),
        "porCentroCusto": _agrupar(rows, "porCentroCusto", "NomeCCusto", pendente_key, realizado_key),
    }


pagar_resumo_fixture = _resumo_agrupado_fixture(pagar_rows, "TOTAL GERAL", "APagar", "Pago")
receber_resumo_fixture = _resumo_agrupado_fixture(receber_rows, "TOTAL GERAL", "AReceber", "Recebido")


# ---------------------------------------------------------------------------
# Histórico (comparação mês atual x mês anterior) - modo demo.
# Sintetiza um "mês anterior" plausível perturbando os valores atuais por
# fornecedor/cliente, só pra ter algo coerente pra comparar na demo. Em
# produção isso vem de uma segunda consulta real ao HANO (mês anterior de
# verdade) - ver db.py fetch_pagar_comparativo / fetch_receber_comparativo.
# ---------------------------------------------------------------------------

def _comparar_por_nome_fixture(rows, nome_key, valor_key, pendente_key, top_n=10):
    atual = {}
    for r in rows:
        nome = r[nome_key]
        atual[nome] = atual.get(nome, 0.0) + r[valor_key]

    # "mês anterior" sintético: fator aleatório 0.6x-1.4x sobre o total já
    # somado do atual, com ~15% de chance do fornecedor/cliente não ter
    # existido antes (simula entrada de novo parceiro).
    anterior = {}
    for nome, valor_atual_total in atual.items():
        if random.random() < 0.15:
            anterior[nome] = 0.0
        else:
            anterior[nome] = valor_atual_total * random.uniform(0.6, 1.4)

    nomes = set(atual) | set(anterior)
    itens = []
    for nome in nomes:
        a = atual.get(nome, 0.0)
        p = anterior.get(nome, 0.0)
        variacao = a - p
        pct = (variacao / p * 100) if p else (100.0 if a else 0.0)
        pendente = sum(r[pendente_key] for r in rows if r[nome_key] == nome)
        itens.append({
            "nome": nome, "atual": brl(a), "anterior": brl(p),
            "variacao": brl(variacao), "variacaoPct": round(pct, 1),
            "pendente": brl(pendente),
        })
    itens.sort(key=lambda x: abs(x["variacao"]), reverse=True)

    total_atual = brl(sum(atual.values()))
    total_anterior = brl(sum(anterior.values()))
    variacao_total = brl(total_atual - total_anterior)
    pct_total = (variacao_total / total_anterior * 100) if total_anterior else (100.0 if total_atual else 0.0)

    return {
        "totalAtual": total_atual, "totalAnterior": total_anterior,
        "variacao": variacao_total, "variacaoPct": round(pct_total, 1),
        "itens": itens[:top_n],
    }


pagar_comp_fixture = _comparar_por_nome_fixture(pagar_rows, "NomeFornec", "ValorMes", "APagar")
receber_comp_fixture = _comparar_por_nome_fixture(receber_rows, "NomeCliente", "ValorMes", "AReceber")

# Disponibilidade: usa a série de FLUXO DIÁRIO já gerada (últimos N dias) e
# sintetiza uma "série anterior" com leve tendência diferente, só pra dar
# pra desenhar as duas linhas na demo.
serie_atual_disp = [r["DisponibilidadeProjetada"] for r in resumo_rows if r["TipoLinha"] == "FLUXO DIÁRIO"]
fator_tendencia = random.uniform(0.85, 1.05)
serie_anterior_disp = [brl(v * fator_tendencia * random.uniform(0.97, 1.03)) for v in serie_atual_disp]

historico_fixture = {
    "periodoAtual": {"de": (START).isoformat(), "ate": (START + timedelta(days=N_DAYS - 1)).isoformat()},
    "periodoAnterior": {"de": None, "ate": None},
    "disponibilidade": {
        "serieAtual": serie_atual_disp,
        "serieAnterior": serie_anterior_disp,
        "finalAtual": serie_atual_disp[-1] if serie_atual_disp else None,
        "finalAnterior": serie_anterior_disp[-1] if serie_anterior_disp else None,
        "variacao": brl(serie_atual_disp[-1] - serie_anterior_disp[-1]) if serie_atual_disp and serie_anterior_disp else None,
    },
    "pagar": pagar_comp_fixture,
    "receber": receber_comp_fixture,
}

# ---------------------------------------------------------------------------
with open(f"{OUT}/fluxo_resumo.json", "w", encoding="utf-8") as f:
    json.dump(resumo_rows, f, ensure_ascii=False, indent=2)

with open(f"{OUT}/fluxo_detalhe.json", "w", encoding="utf-8") as f:
    json.dump(detalhe_rows, f, ensure_ascii=False, indent=2)

with open(f"{OUT}/pagar.json", "w", encoding="utf-8") as f:
    json.dump(pagar_out, f, ensure_ascii=False, indent=2)

with open(f"{OUT}/receber.json", "w", encoding="utf-8") as f:
    json.dump(receber_out, f, ensure_ascii=False, indent=2)

with open(f"{OUT}/pagar_resumo.json", "w", encoding="utf-8") as f:
    json.dump(pagar_resumo_fixture, f, ensure_ascii=False, indent=2)

with open(f"{OUT}/receber_resumo.json", "w", encoding="utf-8") as f:
    json.dump(receber_resumo_fixture, f, ensure_ascii=False, indent=2)

with open(f"{OUT}/historico.json", "w", encoding="utf-8") as f:
    json.dump(historico_fixture, f, ensure_ascii=False, indent=2)

print(f"resumo: {len(resumo_rows)} linhas")
print(f"detalhe: {len(detalhe_rows)} linhas")
print(f"pagar: {len(pagar_out)} linhas (incl. total geral)")
print(f"receber: {len(receber_out)} linhas (incl. total geral)")
print("pagar_resumo / receber_resumo: gerados")
print("historico: gerado")
