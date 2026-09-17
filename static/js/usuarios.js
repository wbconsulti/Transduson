// Página de gestão de usuários - Transduson

function esc(v) {
  if (v === null || v === undefined) return "";
  return String(v).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

async function carregarUsuarios() {
  const resp = await fetch("/api/auth/users");
  if (resp.status === 401) { window.location.href = "/login"; return; }
  const usuarios = await resp.json();
  const tabela = document.getElementById("usuarios-table");
  const linhas = usuarios.map((u) => `<tr><td>${esc(u.nome)}</td><td>${esc(u.email)}</td></tr>`).join("");
  tabela.innerHTML = `<thead><tr><th>Nome</th><th>E-mail</th></tr></thead><tbody>${linhas}</tbody>`;
}

document.getElementById("form-novo-usuario").addEventListener("submit", async (e) => {
  e.preventDefault();
  const msg = document.getElementById("novo-msg");
  msg.textContent = "";
  msg.className = "usuarios-msg";

  const nome = document.getElementById("novo-nome").value;
  const email = document.getElementById("novo-email").value;
  const senha = document.getElementById("novo-senha").value;

  try {
    const resp = await fetch("/api/auth/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ nome, email, senha }),
    });
    const data = await resp.json().catch(() => null);
    if (!resp.ok) {
      msg.textContent = (data && data.detail) || "Não foi possível criar o usuário.";
      msg.classList.add("erro");
      return;
    }
    msg.textContent = `Usuário "${nome}" criado.`;
    msg.classList.add("ok");
    document.getElementById("form-novo-usuario").reset();
    carregarUsuarios();
  } catch {
    msg.textContent = "Falha de conexão com o servidor.";
    msg.classList.add("erro");
  }
});

carregarUsuarios();
