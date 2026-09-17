// Tela de login - Transduson

async function submitAuth(url, body, erroElId) {
  const erroEl = document.getElementById(erroElId);
  erroEl.textContent = "";
  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const data = await resp.json().catch(() => null);
    if (!resp.ok) {
      erroEl.textContent = (data && data.detail) || "Não foi possível concluir.";
      return;
    }
    window.location.href = "/";
  } catch (err) {
    erroEl.textContent = "Falha de conexão com o servidor.";
  }
}

document.getElementById("form-entrar").addEventListener("submit", (e) => {
  e.preventDefault();
  submitAuth("/api/auth/login", {
    email: document.getElementById("entrar-email").value,
    senha: document.getElementById("entrar-senha").value,
  }, "entrar-erro");
});
