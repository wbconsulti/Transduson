// Painel de Fluxo de Caixa - Transduson (v1 demo)
// JS puro, sem framework, sem lib de gráficos.

const state = {
  resumo: [],
  detalhe: [],
  pagar: [],
  receber: [],
  pagarResumo: null,
  receberResumo: null,
  historico: null,
};

// Guarda as linhas efetivamente exibidas (já filtradas) em cada tela, pra
// exportar exatamente o que a pessoa está vendo.
const currentRows = { resumo: [], detalhe: [], pagar: [], receber: [], historico: [] };

// ---------------------------------------------------------------- helpers

function fmtBRL(v) {
  if (v === null || v === undefined || v === "") return "—";
  return Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

function fmtDate(iso) {
  if (!iso) return "—";
  // Alguns campos voltam do HANA como timestamp completo
  // ("2026-08-15T00:00:00") em vez de só a data - pega só os 10
  // primeiros chars (YYYY-MM-DD) antes de reformatar.
  const datePart = String(iso).slice(0, 10);
  const [y, m, d] = datePart.split("-");
  if (!y || !m || !d) return String(iso);
  return `${d}/${m}/${y}`;
}

// Os campos de data são <input type="text"> com máscara dd/mm/aaaa
// própria - não usamos <input type="date"> porque o formato nativo dele
// segue o idioma do Windows/navegador, não o da página (então a máquina
// do cliente mostrava mm/dd/aaaa mesmo com o site em pt-BR).

function isoToBr(iso) {
  if (!iso) return "";
  return fmtDate(iso) === "—" ? "" : fmtDate(iso);
}

function brToIso(br) {
  const m = String(br || "").trim().match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (!m) return "";
  const [, d, mo, y] = m;
  return `${y}-${mo}-${d}`;
}

function attachDateMask(input) {
  input.addEventListener("input", () => {
    let digits = input.value.replace(/\D/g, "").slice(0, 8);
    let out = digits;
    if (digits.length > 4) out = `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`;
    else if (digits.length > 2) out = `${digits.slice(0, 2)}/${digits.slice(2)}`;
    input.value = out;
  });
}

function getDateValue(id) {
  return brToIso(document.getElementById(id).value);
}

function setDateValue(id, iso) {
  document.getElementById(id).value = isoToBr(iso);
}

function esc(v) {
  if (v === null || v === undefined) return "";
  return String(v).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

// Toda chamada à API passa por aqui - se o backend responder com erro
// (500/502 etc.), joga uma exceção com a mensagem real (detail) em vez de
// devolver o objeto de erro como se fosse dado, que quebrava telas
// silenciosamente (ex: "state.resumo.filter is not a function").
async function fetchJson(url) {
  const resp = await fetch(url);
  if (resp.status === 401) {
    window.location.href = "/login";
    return new Promise(() => {}); // nunca resolve - a página já está navegando
  }
  let body;
  try {
    body = await resp.json();
  } catch {
    body = null;
  }
  if (!resp.ok) {
    const msg = (body && body.detail) || `${resp.status} ${resp.statusText}`;
    throw new Error(`${url} → ${msg}`);
  }
  return body;
}

function numClass(v) {
  if (v === null || v === undefined || v === "") return "";
  return Number(v) < 0 ? "neg" : "";
}

function statusClass(s) {
  const map = {
    "Pago": "st-pago", "Recebido": "st-recebido", "Confirmado": "st-confirmado",
    "Vencido": "st-vencido", "Previsto": "st-previsto",
  };
  return map[s] || "";
}

function buildTable(el, columns, rows, opts = {}) {
  if (!rows.length) {
    el.innerHTML = `<tbody><tr class="empty-row"><td>Nenhum registro para os filtros selecionados.</td></tr></tbody>`;
    return;
  }
  const thead = `<thead><tr>${columns.map((c) => `<th>${c.label}</th>`).join("")}</tr></thead>`;
  const body = rows.map((row) => {
    const isTotal = opts.totalKey && row[opts.totalKey] === opts.totalValue;
    const cells = columns.map((c) => {
      const raw = row[c.key];
      if (c.type === "money") {
        return `<td class="num ${numClass(raw)}">${fmtBRL(raw)}</td>`;
      }
      if (c.type === "date") {
        return `<td>${fmtDate(raw)}</td>`;
      }
      if (c.type === "status") {
        return raw ? `<td><span class="status-chip ${statusClass(raw)}">${esc(raw)}</span></td>` : "<td>—</td>";
      }
      return `<td>${raw === null || raw === undefined || raw === "" ? "—" : esc(raw)}</td>`;
    }).join("");
    return `<tr${isTotal ? ' class="row-total"' : ""}>${cells}</tr>`;
  }).join("");
  el.innerHTML = thead + `<tbody>${body}</tbody>`;
}

function fillSelect(select, values, placeholder) {
  const current = select.value;
  select.innerHTML = `<option value="">${placeholder}</option>` +
    values.map((v) => `<option value="${esc(v)}">${esc(v)}</option>`).join("");
  if (values.includes(current)) select.value = current;
}

function uniqueSorted(rows, key) {
  return [...new Set(rows.map((r) => r[key]).filter((v) => v !== null && v !== undefined && v !== ""))].sort();
}

// ---------------------------------------------------------------- nav

document.querySelectorAll(".tab").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach((b) => b.classList.remove("is-active"));
    document.querySelectorAll(".screen").forEach((s) => s.classList.remove("is-active"));
    btn.classList.add("is-active");
    document.getElementById(`screen-${btn.dataset.screen}`).classList.add("is-active");
  });
});

document.querySelectorAll(".view-toggle-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".view-toggle-btn").forEach((b) => b.classList.remove("is-active"));
    btn.classList.add("is-active");
    document.querySelectorAll(".resumo-view").forEach((v) => v.classList.remove("is-active"));
    document.getElementById(`resumo-view-${btn.dataset.view}`).classList.add("is-active");
    const isDash = btn.dataset.view === "dash";
    document.getElementById("resumo-de-field").style.display = isDash ? "none" : "";
    document.getElementById("resumo-ate-field").style.display = isDash ? "none" : "";
  });
});

// ---------------------------------------------------------------- export CSV

function toCsvValue(v) {
  if (v === null || v === undefined) return "";
  const s = String(v);
  return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function exportCsv(columns, rows, filename) {
  if (!rows.length) return;
  const header = columns.map((c) => toCsvValue(c.label)).join(";");
  const lines = rows.map((row) =>
    columns.map((c) => {
      const raw = row[c.key];
      if (c.type === "date") return toCsvValue(fmtDate(raw));
      if (c.type === "money") return toCsvValue(raw === null || raw === undefined ? "" : Number(raw).toFixed(2).replace(".", ","));
      return toCsvValue(raw);
    }).join(";")
  );
  const csv = "\uFEFF" + [header, ...lines].join("\r\n"); // BOM p/ Excel abrir acentuação certo
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

// ---------------------------------------------------------------- TELA 1: resumo

// A tela 1 recebe 3 "tipos de linha" reais do HANA (não é mais "1 linha por
// banco por dia"): SALDO POR BANCO / TOTAL DOS BANCOS (posição de abertura,
// só no dia anterior ao período) e FLUXO DIÁRIO (consolidado da empresa,
// Banco=null, um por dia - porque movimento futuro ainda não tem banco
// definido no SAP).

const ABERTURA_COLS = [
  { key: "Banco", label: "Banco" },
  { key: "UltimaDataMovimento", label: "Últ. movimento", type: "date" },
  { key: "UltimaConciliacao", label: "Última conciliação", type: "date" },
  { key: "DisponibilidadeAnterior", label: "Disponibilidade", type: "money" },
];

// Linhas de abertura (SALDO POR BANCO + TOTAL DOS BANCOS) vêm do resumo -
// reaproveitadas também na tela de Detalhe, então ficam numa função só.
function getAberturaRows() {
  return state.resumo
    .filter((r) => r.TipoLinha === "SALDO POR BANCO" || r.TipoLinha === "TOTAL DOS BANCOS")
    .sort((a, b) => (a.TipoLinha === "TOTAL DOS BANCOS" ? 0 : 1) - (b.TipoLinha === "TOTAL DOS BANCOS" ? 0 : 1));
}

const RESUMO_COLS = [
  { key: "DataFluxo", label: "Data", type: "date" },
  { key: "RecebRealizado", label: "Receb. realizado", type: "money" },
  { key: "PedVenda", label: "Ped. venda", type: "money" },
  { key: "NFReceber", label: "NF a receber", type: "money" },
  { key: "CartaoCredito", label: "Cartão crédito", type: "money" },
  { key: "TotalReceber", label: "Total a receber", type: "money" },
  { key: "PagtoRealizado", label: "Pagto. realizado", type: "money" },
  { key: "PedCompra", label: "Ped. compra", type: "money" },
  { key: "NFPagar", label: "NF a pagar", type: "money" },
  { key: "TotalPagar", label: "Total a pagar", type: "money" },
  { key: "ResultadoDia", label: "Resultado dia", type: "money" },
  { key: "DisponibilidadeProjetada", label: "Disp. projetada", type: "money" },
];

function renderResumo() {
  const abertura = getAberturaRows();
  const diario = state.resumo
    .filter((r) => r.TipoLinha === "FLUXO DIÁRIO")
    .sort((a, b) => a.DataFluxo.localeCompare(b.DataFluxo));

  const dataAbertura = abertura.find((r) => r.TipoLinha === "SALDO POR BANCO");
  document.getElementById("resumo-abertura-hint").textContent =
    dataAbertura ? `Posição em ${fmtDate(dataAbertura.DataFluxo)}` : "";

  buildTable(document.getElementById("resumo-abertura-table"), ABERTURA_COLS, abertura, {
    totalKey: "TipoLinha", totalValue: "TOTAL DOS BANCOS",
  });
  buildTable(document.getElementById("resumo-table"), RESUMO_COLS, diario);
  currentRows.resumo = diario;
  drawResumoChart(diario);
}

function drawResumoChart(diario) {
  const el = document.getElementById("resumo-chart");
  if (!diario.length) { el.innerHTML = ""; return; }

  const dias = diario.map((r) => r.DataFluxo);
  const perDia = diario.map((r) => r.DisponibilidadeProjetada);

  const W = 900, H = 220, padL = 66, padR = 16, padT = 14, padB = 26;
  const plotW = W - padL - padR, plotH = H - padT - padB;

  const min = Math.min(...perDia), max = Math.max(...perDia);
  const range = max - min || 1;
  const yFor = (v) => padT + plotH - ((v - min) / range) * plotH;
  const xFor = (i) => padL + (i / (perDia.length - 1 || 1)) * plotW;

  const linePts = perDia.map((v, i) => `${xFor(i)},${yFor(v)}`).join(" ");
  const areaPts = `${padL},${padT + plotH} ${linePts} ${padL + plotW},${padT + plotH}`;

  const gridLines = [0, 0.5, 1].map((f) => {
    const y = padT + plotH * f;
    const val = max - range * f;
    return `<line x1="${padL}" y1="${y}" x2="${padL + plotW}" y2="${y}" stroke="var(--border-soft, #232830)" stroke-width="1" />
      <text x="${padL - 10}" y="${y + 4}" text-anchor="end" font-size="10.5" font-family="IBM Plex Mono, monospace" fill="var(--text-muted, #8b93a1)">${fmtBRL(val).replace("R$", "R$\u00A0")}</text>`;
  }).join("");

  const xLabels = perDia.map((_, i) => {
    if (i !== 0 && i !== perDia.length - 1 && i % Math.ceil(perDia.length / 6) !== 0) return "";
    return `<text x="${xFor(i)}" y="${H - 6}" text-anchor="middle" font-size="10.5" font-family="IBM Plex Mono, monospace" fill="var(--text-muted, #8b93a1)">${fmtDate(dias[i]).slice(0, 5)}</text>`;
  }).join("");

  const dots = perDia.map((v, i) => `<circle cx="${xFor(i)}" cy="${yFor(v)}" r="2.5" fill="var(--accent-pos, #2fb6a3)" />`).join("");

  el.innerHTML = `
    <svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="areaFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#2fb6a3" stop-opacity="0.22" />
          <stop offset="100%" stop-color="#2fb6a3" stop-opacity="0" />
        </linearGradient>
      </defs>
      ${gridLines}
      <polygon points="${areaPts}" fill="url(#areaFill)" />
      <polyline points="${linePts}" fill="none" stroke="#2fb6a3" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
      ${dots}
      ${xLabels}
    </svg>`;
}

// ---------------------------------------------------------------- TELA 1: dashboard Pagar & Receber

function renderDashKpis(pagarResumo, receberResumo) {
  const p = (pagarResumo && pagarResumo.total) || {};
  const r = (receberResumo && receberResumo.total) || {};
  document.getElementById("dash-kpis").innerHTML = `
    <div class="tot-cell"><div class="tot-label">Pagar · valor do mês</div><div class="tot-value">${fmtBRL(p.ValorMes)}</div></div>
    <div class="tot-cell"><div class="tot-label">Pagar · pendente</div><div class="tot-value" style="color:var(--accent-neg)">${fmtBRL(p.Pendente)}</div></div>
    <div class="tot-cell"><div class="tot-label">Pagar · pago</div><div class="tot-value" style="color:var(--accent-pos)">${fmtBRL(p.Realizado)}</div></div>
    <div class="tot-cell"><div class="tot-label">Receber · valor do mês</div><div class="tot-value">${fmtBRL(r.ValorMes)}</div></div>
    <div class="tot-cell"><div class="tot-label">Receber · pendente</div><div class="tot-value" style="color:var(--accent-warn)">${fmtBRL(r.Pendente)}</div></div>
    <div class="tot-cell"><div class="tot-label">Receber · recebido</div><div class="tot-value" style="color:var(--accent-pos)">${fmtBRL(r.Realizado)}</div></div>
  `;
}

function renderDashBlock(containerId, items, colorClass) {
  const el = document.getElementById(containerId);
  if (!items || !items.length) {
    el.innerHTML = `<div class="dash-bar-row"><span class="dash-bar-label">Sem dados</span></div>`;
    return;
  }
  const sorted = [...items].sort((a, b) => (b.ValorMes || 0) - (a.ValorMes || 0));
  const max = Math.max(...sorted.map((i) => i.ValorMes || 0), 1);
  el.innerHTML = sorted.map((i) => {
    const pct = Math.max(2, ((i.ValorMes || 0) / max) * 100);
    return `
      <div class="dash-bar-row">
        <span class="dash-bar-label" title="${esc(i.Rotulo ?? "—")}">${esc(i.Rotulo ?? "—")}</span>
        <span class="dash-bar-track"><span class="dash-bar-fill ${colorClass}" style="width:${pct}%"></span></span>
        <span class="dash-bar-value">${fmtBRL(i.ValorMes)}</span>
      </div>`;
  }).join("");
}

function renderDashboards() {
  renderDashKpis(state.pagarResumo, state.receberResumo);
  const p = state.pagarResumo || {};
  const r = state.receberResumo || {};
  renderDashBlock("dash-pagar-status", p.porStatus, "neg");
  renderDashBlock("dash-pagar-cfo", p.porCFO, "neg");
  renderDashBlock("dash-pagar-centro", p.porCentroCusto, "neg");
  renderDashBlock("dash-receber-status", r.porStatus, "pos");
  renderDashBlock("dash-receber-cfo", r.porCFO, "pos");
  renderDashBlock("dash-receber-centro", r.porCentroCusto, "pos");
}

// ---------------------------------------------------------------- TELA 2: detalhe

const DETALHE_COLS = [
  { key: "DataFluxo", label: "Data", type: "date" },
  { key: "GrupoMovimento", label: "Grupo" },
  { key: "Natureza", label: "Natureza" },
  { key: "Origem", label: "Origem" },
  { key: "Descricao", label: "Descrição" },
  { key: "Parceiro", label: "Parceiro" },
  { key: "DocSAP", label: "Doc. SAP" },
  { key: "Parcela", label: "Parcela" },
  { key: "Receber", label: "Receber", type: "money" },
  { key: "Pagar", label: "Pagar", type: "money" },
  { key: "NomeCFO", label: "CFO" },
  { key: "NomeCCusto", label: "C. custo" },
  { key: "Observacao", label: "Observação" },
];

function renderDetalhe() {
  const de = getDateValue("detalhe-de");
  const ate = getDateValue("detalhe-ate");
  const cfo = document.getElementById("detalhe-cfo-filter").value;

  buildTable(document.getElementById("detalhe-abertura-table"), ABERTURA_COLS, getAberturaRows(), {
    totalKey: "TipoLinha", totalValue: "TOTAL DOS BANCOS",
  });

  const rows = state.detalhe.filter((r) => {
    if (de && r.DataFluxo < de) return false;
    if (ate && r.DataFluxo > ate) return false;
    if (cfo && r.NomeCFO !== cfo) return false;
    return true;
  }).sort((a, b) => a.DataFluxo.localeCompare(b.DataFluxo));

  const totalReceber = rows.reduce((s, r) => s + r.Receber, 0);
  const totalPagar = rows.reduce((s, r) => s + r.Pagar, 0);
  document.getElementById("detalhe-meta").textContent =
    `${rows.length} movimentos · a receber ${fmtBRL(totalReceber)} · a pagar ${fmtBRL(totalPagar)}`;

  buildTable(document.getElementById("detalhe-table"), DETALHE_COLS, rows);
  currentRows.detalhe = rows;
}

// ---------------------------------------------------------------- TELA 3: pagar

const PAGAR_COLS = [
  { key: "Vencimento", label: "Vencimento", type: "date" },
  { key: "StatusPrevisao", label: "Status", type: "status" },
  { key: "NomeFornec", label: "Fornecedor" },
  { key: "ValorMes", label: "Valor mês", type: "money" },
  { key: "ImpRet", label: "Imp. retido", type: "money" },
  { key: "LancadoNF", label: "Lançado NF", type: "money" },
  { key: "APagar", label: "A pagar", type: "money" },
  { key: "Pago", label: "Pago", type: "money" },
  { key: "DataPagto", label: "Data pagto.", type: "date" },
  { key: "Parcela", label: "Parcela" },
  { key: "NomeCFO", label: "CFO" },
  { key: "NomeCCusto", label: "C. custo" },
  { key: "ContaPagamento", label: "Conta" },
];

function renderPagar() {
  const status = document.getElementById("pagar-status-filter").value;
  const cfo = document.getElementById("pagar-cfo-filter").value;
  const busca = document.getElementById("pagar-fornec-filter").value.trim().toLowerCase();

  const detalhes = state.pagar.filter((r) => r.TipoLinha === "DETALHE").filter((r) => {
    if (status && r.StatusPrevisao !== status) return false;
    if (cfo && r.NomeCFO !== cfo) return false;
    if (busca && !r.NomeFornec.toLowerCase().includes(busca)) return false;
    return true;
  }).sort((a, b) => a.Vencimento.localeCompare(b.Vencimento));

  const totalValor = detalhes.reduce((s, r) => s + r.ValorMes, 0);
  const totalPago = detalhes.reduce((s, r) => s + r.Pago, 0);
  const totalAPagar = detalhes.reduce((s, r) => s + r.APagar, 0);

  document.getElementById("pagar-totalizer").innerHTML = `
    <div class="tot-cell"><div class="tot-label">Parcelas filtradas</div><div class="tot-value">${detalhes.length}</div></div>
    <div class="tot-cell"><div class="tot-label">Valor do mês</div><div class="tot-value">${fmtBRL(totalValor)}</div></div>
    <div class="tot-cell"><div class="tot-label">Pago</div><div class="tot-value" style="color:var(--accent-pos)">${fmtBRL(totalPago)}</div></div>
    <div class="tot-cell"><div class="tot-label">A pagar</div><div class="tot-value" style="color:var(--accent-neg)">${fmtBRL(totalAPagar)}</div></div>
  `;

  buildTable(document.getElementById("pagar-table"), PAGAR_COLS, detalhes);
  currentRows.pagar = detalhes;
}

// ---------------------------------------------------------------- TELA 4: receber

const RECEBER_COLS = [
  { key: "Vencimento", label: "Vencimento", type: "date" },
  { key: "StatusPrevisao", label: "Status", type: "status" },
  { key: "NomeCliente", label: "Cliente" },
  { key: "ValorMes", label: "Valor mês", type: "money" },
  { key: "ImpRet", label: "Imp. retido", type: "money" },
  { key: "LancadoNF", label: "Lançado NF", type: "money" },
  { key: "AReceber", label: "A receber", type: "money" },
  { key: "Recebido", label: "Recebido", type: "money" },
  { key: "DataReceb", label: "Data receb.", type: "date" },
  { key: "Parcela", label: "Parcela" },
  { key: "NomeCFO", label: "CFO" },
  { key: "NomeCCusto", label: "C. custo" },
  { key: "ContaRecebimento", label: "Conta" },
];

function renderReceber() {
  const status = document.getElementById("receber-status-filter").value;
  const cfo = document.getElementById("receber-cfo-filter").value;
  const busca = document.getElementById("receber-cliente-filter").value.trim().toLowerCase();

  const detalhes = state.receber.filter((r) => r.TipoLinha === "DETALHE").filter((r) => {
    if (status && r.StatusPrevisao !== status) return false;
    if (cfo && r.NomeCFO !== cfo) return false;
    if (busca && !r.NomeCliente.toLowerCase().includes(busca)) return false;
    return true;
  }).sort((a, b) => a.Vencimento.localeCompare(b.Vencimento));

  const totalValor = detalhes.reduce((s, r) => s + r.ValorMes, 0);
  const totalRecebido = detalhes.reduce((s, r) => s + r.Recebido, 0);
  const totalAReceber = detalhes.reduce((s, r) => s + r.AReceber, 0);

  document.getElementById("receber-totalizer").innerHTML = `
    <div class="tot-cell"><div class="tot-label">Parcelas filtradas</div><div class="tot-value">${detalhes.length}</div></div>
    <div class="tot-cell"><div class="tot-label">Valor do mês</div><div class="tot-value">${fmtBRL(totalValor)}</div></div>
    <div class="tot-cell"><div class="tot-label">Recebido</div><div class="tot-value" style="color:var(--accent-pos)">${fmtBRL(totalRecebido)}</div></div>
    <div class="tot-cell"><div class="tot-label">A receber</div><div class="tot-value" style="color:var(--accent-warn)">${fmtBRL(totalAReceber)}</div></div>
  `;

  buildTable(document.getElementById("receber-table"), RECEBER_COLS, detalhes);
  currentRows.receber = detalhes;
}

// ---------------------------------------------------------------- TELA 5: histórico

function gerarNarrativa(data) {
  const frases = [];
  const disp = data.disponibilidade || {};
  if (disp.finalAtual != null && disp.finalAnterior != null) {
    const dir = disp.variacao >= 0 ? "acima" : "abaixo";
    frases.push(`Disponibilidade projetada fechou em ${fmtBRL(disp.finalAtual)}, ${fmtBRL(Math.abs(disp.variacao))} ${dir} do mesmo ponto do mês anterior (${fmtBRL(disp.finalAnterior)}).`);
  }

  const p = data.pagar || {};
  if (p.totalAtual != null) {
    const dir = p.variacaoPct >= 0 ? "aumento" : "queda";
    frases.push(`Contas a pagar: ${fmtBRL(p.totalAtual)} no mês, ${dir} de ${Math.abs(p.variacaoPct).toFixed(1)}% frente ao mês anterior (${fmtBRL(p.totalAnterior)}).`);
  }
  if (p.itens && p.itens[0]) {
    const top = p.itens[0];
    const dir = top.variacao >= 0 ? "aumentou" : "reduziu";
    frases.push(`Maior variação em fornecedores: ${top.nome} ${dir} ${fmtBRL(Math.abs(top.variacao))} frente ao mês anterior.`);
  }

  const r = data.receber || {};
  if (r.totalAtual != null) {
    const dir = r.variacaoPct >= 0 ? "aumento" : "queda";
    frases.push(`Contas a receber: ${fmtBRL(r.totalAtual)} no mês, ${dir} de ${Math.abs(r.variacaoPct).toFixed(1)}% frente ao mês anterior (${fmtBRL(r.totalAnterior)}).`);
  }
  if (r.itens && r.itens[0]) {
    const top = r.itens[0];
    const dir = top.variacao >= 0 ? "aumentou" : "reduziu";
    frases.push(`Maior variação em clientes: ${top.nome} ${dir} ${fmtBRL(Math.abs(top.variacao))} frente ao mês anterior.`);
  }
  return frases;
}

function renderHistoricoNarrativa(data) {
  const frases = gerarNarrativa(data);
  document.getElementById("historico-narrativa").innerHTML =
    frases.length ? frases.map((f) => `<p>${esc(f)}</p>`).join("") : "<p>Sem dados suficientes pra comparar períodos.</p>";
}

function renderHistoricoKpis(data) {
  const p = data.pagar || {}, r = data.receber || {}, d = data.disponibilidade || {};
  const sinal = (v) => (v >= 0 ? "+" : "");
  document.getElementById("historico-kpis").innerHTML = `
    <div class="tot-cell"><div class="tot-label">Disponibilidade atual</div><div class="tot-value">${fmtBRL(d.finalAtual)}</div></div>
    <div class="tot-cell"><div class="tot-label">Pagar · mês atual</div><div class="tot-value" style="color:var(--accent-neg)">${fmtBRL(p.totalAtual)}</div></div>
    <div class="tot-cell"><div class="tot-label">Pagar · variação</div><div class="tot-value">${sinal(p.variacaoPct)}${(p.variacaoPct ?? 0).toFixed(1)}%</div></div>
    <div class="tot-cell"><div class="tot-label">Receber · mês atual</div><div class="tot-value" style="color:var(--accent-pos)">${fmtBRL(r.totalAtual)}</div></div>
    <div class="tot-cell"><div class="tot-label">Receber · variação</div><div class="tot-value">${sinal(r.variacaoPct)}${(r.variacaoPct ?? 0).toFixed(1)}%</div></div>
  `;
}

function drawHistoricoChart(serieAtual, serieAnterior) {
  const el = document.getElementById("historico-chart");
  serieAtual = serieAtual || [];
  serieAnterior = serieAnterior || [];
  if (!serieAtual.length && !serieAnterior.length) { el.innerHTML = ""; return; }

  const n = Math.max(serieAtual.length, serieAnterior.length, 1);
  const W = 900, H = 190, padL = 66, padR = 16, padT = 14, padB = 20;
  const plotW = W - padL - padR, plotH = H - padT - padB;

  const all = [...serieAtual, ...serieAnterior];
  const min = Math.min(...all), max = Math.max(...all);
  const range = max - min || 1;
  const xFor = (i) => padL + (i / (n - 1 || 1)) * plotW;
  const yFor = (v) => padT + plotH - ((v - min) / range) * plotH;
  const pathFor = (serie) => serie.map((v, i) => `${xFor(i)},${yFor(v)}`).join(" ");

  const gridLines = [0, 0.5, 1].map((f) => {
    const y = padT + plotH * f;
    const val = max - range * f;
    return `<line x1="${padL}" y1="${y}" x2="${padL + plotW}" y2="${y}" stroke="var(--border-soft, #232830)" stroke-width="1" />
      <text x="${padL - 10}" y="${y + 4}" text-anchor="end" font-size="10.5" font-family="IBM Plex Mono, monospace" fill="var(--text-muted, #8b93a1)">${fmtBRL(val).replace("R$", "R$\u00A0")}</text>`;
  }).join("");

  el.innerHTML = `
    <svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg">
      ${gridLines}
      <polyline points="${pathFor(serieAnterior)}" fill="none" stroke="var(--text-faint, #5c6472)" stroke-width="2" stroke-dasharray="4,3" stroke-linejoin="round" />
      <polyline points="${pathFor(serieAtual)}" fill="none" stroke="var(--accent-pos, #2fb6a3)" stroke-width="2.2" stroke-linejoin="round" />
    </svg>
    <div style="display:flex; gap:16px; margin-top:4px; font-size:10.5px; color:var(--text-muted);">
      <span><span style="display:inline-block;width:12px;height:2px;background:var(--accent-pos);margin-right:5px;vertical-align:middle;"></span>Mês atual</span>
      <span><span style="display:inline-block;width:12px;height:0;border-top:2px dashed var(--text-faint);margin-right:5px;vertical-align:middle;"></span>Mês anterior</span>
    </div>`;
}

function renderHistoricoTable(elId, itens, tipo) {
  const el = document.getElementById(elId);
  if (!itens || !itens.length) {
    el.innerHTML = `<tbody><tr class="empty-row"><td>Sem dados para comparar.</td></tr></tbody>`;
    return;
  }
  const head = `<thead><tr><th>Nome</th><th>Atual</th><th>Anterior</th><th>Variação</th><th>Var. %</th></tr></thead>`;
  const body = itens.map((it) => {
    const aumento = it.variacao >= 0;
    // Pagar: aumento de gasto é "atenção" (vermelho). Receber: aumento de receita é "bom" (verde).
    const cls = tipo === "pagar" ? (aumento ? "neg" : "pos") : (aumento ? "pos" : "neg");
    const sinal = aumento ? "+" : "";
    return `<tr>
      <td>${esc(it.nome)}</td>
      <td class="num">${fmtBRL(it.atual)}</td>
      <td class="num">${fmtBRL(it.anterior)}</td>
      <td class="num ${cls}">${sinal}${fmtBRL(it.variacao)}</td>
      <td class="num ${cls}">${sinal}${it.variacaoPct.toFixed(1)}%</td>
    </tr>`;
  }).join("");
  el.innerHTML = head + `<tbody>${body}</tbody>`;
}

const HISTORICO_EXPORT_COLS = [
  { key: "Tipo", label: "Tipo" },
  { key: "nome", label: "Nome" },
  { key: "atual", label: "Atual", type: "money" },
  { key: "anterior", label: "Anterior", type: "money" },
  { key: "variacao", label: "Variação", type: "money" },
  { key: "variacaoPct", label: "Variação %" },
];

function renderHistorico() {
  const data = state.historico;
  if (!data) return;

  renderHistoricoNarrativa(data);
  renderHistoricoKpis(data);
  drawHistoricoChart(data.disponibilidade && data.disponibilidade.serieAtual, data.disponibilidade && data.disponibilidade.serieAnterior);
  renderHistoricoTable("historico-pagar-table", data.pagar && data.pagar.itens, "pagar");
  renderHistoricoTable("historico-receber-table", data.receber && data.receber.itens, "receber");

  const pa = data.periodoAtual, pp = data.periodoAnterior;
  if (pa && pa.de) {
    const periodoAnteriorTxt = pp && pp.de ? `${fmtDate(pp.de)} – ${fmtDate(pp.ate)}` : "o mês anterior";
    document.getElementById("historico-periodo-desc").textContent =
      `${fmtDate(pa.de)} – ${fmtDate(pa.ate)} comparado com ${periodoAnteriorTxt}`;
  }

  currentRows.historico = [
    ...(data.pagar && data.pagar.itens || []).map((it) => ({ Tipo: "Fornecedor", ...it })),
    ...(data.receber && data.receber.itens || []).map((it) => ({ Tipo: "Cliente", ...it })),
  ];
}

function isoDaysAgo(n) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
}

function isoDaysAhead(n) {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
}

function isoFirstDayOfMonth() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().slice(0, 10);
}

function isoLastDayOfMonth() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth() + 1, 0).toISOString().slice(0, 10);
}

async function reloadResumo() {
  const de = getDateValue("resumo-de");
  const ate = getDateValue("resumo-ate");
  const qs = de && ate ? `?de=${de}&ate=${ate}` : "";
  state.resumo = await fetchJson(`/api/fluxo-resumo${qs}`);
  renderResumo();
}

async function reloadPagar() {
  const de = getDateValue("pagar-de");
  const ate = getDateValue("pagar-ate");
  const qs = de && ate ? `?de=${de}&ate=${ate}` : "";
  state.pagar = await fetchJson(`/api/pagar${qs}`);
  renderPagar();
}

async function reloadReceber() {
  const de = getDateValue("receber-de");
  const ate = getDateValue("receber-ate");
  const qs = de && ate ? `?de=${de}&ate=${ate}` : "";
  state.receber = await fetchJson(`/api/receber${qs}`);
  renderReceber();
}

async function loadSourcePill() {
  const pill = document.getElementById("source-pill");
  try {
    const health = await fetchJson("/api/health");
    if (health.config.use_fixtures) {
      pill.textContent = "Dados demo";
      pill.classList.add("is-demo");
    } else {
      pill.textContent = "HANA · produção";
      pill.classList.add("is-live");
    }
  } catch {
    pill.textContent = "";
  }
}

async function loadUserInfo() {
  try {
    const me = await fetchJson("/api/auth/me");
    document.getElementById("user-name").textContent = me.nome;
  } catch {
    // fetchJson já redireciona pro /login em caso de 401
  }
}

document.getElementById("logout-btn").addEventListener("click", async () => {
  try {
    await fetch("/api/auth/logout", { method: "POST" });
  } finally {
    window.location.href = "/login";
  }
});

function wireExportButtons() {
  document.getElementById("resumo-export-btn").addEventListener("click", () =>
    exportCsv(RESUMO_COLS, currentRows.resumo, `fluxo-diario_${isoDaysAgo(0)}.csv`));
  document.getElementById("detalhe-export-btn").addEventListener("click", () =>
    exportCsv(DETALHE_COLS, currentRows.detalhe, `fluxo-detalhe_${isoDaysAgo(0)}.csv`));
  document.getElementById("pagar-export-btn").addEventListener("click", () =>
    exportCsv(PAGAR_COLS, currentRows.pagar, `contas-a-pagar_${isoDaysAgo(0)}.csv`));
  document.getElementById("receber-export-btn").addEventListener("click", () =>
    exportCsv(RECEBER_COLS, currentRows.receber, `contas-a-receber_${isoDaysAgo(0)}.csv`));
  document.getElementById("historico-export-btn").addEventListener("click", () =>
    exportCsv(HISTORICO_EXPORT_COLS, currentRows.historico, `historico-comparativo_${isoDaysAgo(0)}.csv`));
}

// ---------------------------------------------------------------- boot

async function boot() {
  loadSourcePill();
  loadUserInfo();

  document.querySelectorAll(".date-input").forEach(attachDateMask);

  const hoje = isoDaysAgo(0);
  const dezDiasAdiante = isoDaysAhead(10);
  const inicioMes = isoFirstDayOfMonth();
  const fimMes = isoLastDayOfMonth();

  // Convenção: Resumo diário e Detalhe sempre abrem com o dia de acesso +
  // 10 dias à frente (ex: acessou 17/09 -> abre 17/09 a 27/09).
  setDateValue("resumo-de", hoje);
  setDateValue("resumo-ate", dezDiasAdiante);
  setDateValue("detalhe-de", hoje);
  setDateValue("detalhe-ate", dezDiasAdiante);
  setDateValue("pagar-de", inicioMes);
  setDateValue("pagar-ate", fimMes);
  setDateValue("receber-de", inicioMes);
  setDateValue("receber-ate", fimMes);

  const [resumo, detalhe, pagar, receber, pagarResumo, receberResumo, historico] = await Promise.all([
    fetchJson(`/api/fluxo-resumo?de=${hoje}&ate=${dezDiasAdiante}`),
    fetchJson(`/api/fluxo-detalhe?de=${hoje}&ate=${dezDiasAdiante}`),
    fetchJson(`/api/pagar?de=${inicioMes}&ate=${fimMes}`),
    fetchJson(`/api/receber?de=${inicioMes}&ate=${fimMes}`),
    fetchJson(`/api/pagar-resumo?de=${inicioMes}&ate=${fimMes}`),
    fetchJson(`/api/receber-resumo?de=${inicioMes}&ate=${fimMes}`),
    fetchJson("/api/historico"),
  ]);
  state.resumo = resumo;
  state.detalhe = detalhe;
  state.pagar = pagar;
  state.receber = receber;
  state.pagarResumo = pagarResumo;
  state.receberResumo = receberResumo;
  state.historico = historico;

  fillSelect(document.getElementById("detalhe-cfo-filter"), uniqueSorted(detalhe, "NomeCFO"), "Todos");
  fillSelect(document.getElementById("pagar-status-filter"), uniqueSorted(pagar.filter(r => r.TipoLinha === "DETALHE"), "StatusPrevisao"), "Todos");
  fillSelect(document.getElementById("pagar-cfo-filter"), uniqueSorted(pagar.filter(r => r.TipoLinha === "DETALHE"), "NomeCFO"), "Todos");
  fillSelect(document.getElementById("receber-status-filter"), uniqueSorted(receber.filter(r => r.TipoLinha === "DETALHE"), "StatusPrevisao"), "Todos");
  fillSelect(document.getElementById("receber-cfo-filter"), uniqueSorted(receber.filter(r => r.TipoLinha === "DETALHE"), "NomeCFO"), "Todos");

  ["resumo-de", "resumo-ate"].forEach((id) => document.getElementById(id).addEventListener("change", reloadResumo));
  ["detalhe-de", "detalhe-ate", "detalhe-cfo-filter"].forEach((id) => document.getElementById(id).addEventListener("input", renderDetalhe));
  ["pagar-de", "pagar-ate"].forEach((id) => document.getElementById(id).addEventListener("change", reloadPagar));
  ["pagar-status-filter", "pagar-cfo-filter"].forEach((id) => document.getElementById(id).addEventListener("change", renderPagar));
  document.getElementById("pagar-fornec-filter").addEventListener("input", renderPagar);
  ["receber-de", "receber-ate"].forEach((id) => document.getElementById(id).addEventListener("change", reloadReceber));
  ["receber-status-filter", "receber-cfo-filter"].forEach((id) => document.getElementById(id).addEventListener("change", renderReceber));
  document.getElementById("receber-cliente-filter").addEventListener("input", renderReceber);

  wireExportButtons();

  renderResumo();
  renderDetalhe();
  renderPagar();
  renderReceber();
  renderDashboards();
  renderHistorico();
}

boot().catch((err) => {
  document.querySelector(".main").innerHTML =
    `<p style="color:#c7563f">Falha ao carregar dados: ${esc(err.message)}</p>`;
});
