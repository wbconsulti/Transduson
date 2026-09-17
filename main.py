"""
Painel de Fluxo de Caixa - Transduson

Fonte de dados controlada por config.USE_FIXTURES (env var USE_FIXTURES):
- True  (padrão): lê fixtures/*.json (dados demo, sem tocar em nenhum banco).
- False: conecta no HANA via hdbcli. Resumo/Detalhe usam table functions
  reais; Pagar/Receber usam os scripts do Query Manager (ver db.py).

Resumo/Detalhe/Pagar/Receber aceitam `de`/`ate` (e Pagar/Receber também
`corte`) como query string, no formato YYYY-MM-DD. Sem eles, usa uma janela
padrão dos últimos N dias (config.HANA_DEFAULT_DIAS). Em modo fixtures esses
parâmetros são ignorados - a fixture inteira é sempre devolvida.
"""
import json
import logging
from calendar import monthrange
from datetime import date, timedelta
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from fastapi import Cookie, Depends, FastAPI, HTTPException, Query, Response
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel

load_dotenv()

import auth  # noqa: E402
import config  # noqa: E402

logger = logging.getLogger("transduson.painel")

BASE_DIR = Path(__file__).resolve().parent
FIXTURES_DIR = BASE_DIR / "fixtures"
STATIC_DIR = BASE_DIR / "static"

app = FastAPI(title="Painel de Fluxo de Caixa - Transduson")


# ---------------------------------------------------------------------------
# Autenticação - Nome/Email/Senha, sessão por cookie. Ver auth.py.
# ---------------------------------------------------------------------------

class RegistroBody(BaseModel):
    nome: str
    email: str
    senha: str


class LoginBody(BaseModel):
    email: str
    senha: str


def _set_session_cookie(response: Response, token: str) -> None:
    response.set_cookie(
        key=auth.SESSION_COOKIE_NAME,
        value=token,
        httponly=True,
        samesite="lax",
        secure=False,  # rede interna sem TLS por enquanto; revisar se/quando tiver HTTPS
        max_age=auth.SESSION_TTL_HOURS * 3600,
    )


def require_auth(session: Optional[str] = Cookie(None)) -> dict:
    usuario = auth.usuario_da_sessao(session)
    if not usuario:
        raise HTTPException(status_code=401, detail="Sessão expirada ou inexistente. Faça login novamente.")
    return usuario


@app.post("/api/auth/register")
def auth_register(body: RegistroBody, session: Optional[str] = Cookie(None)):
    # Se já existe gente cadastrada, só quem está logado pode criar conta
    # pra outra pessoa (tela "Usuários"). Se AINDA NÃO existe ninguém, é o
    # cadastro inicial (bootstrap do primeiro admin) - libera sem sessão,
    # senão ninguém conseguiria criar a primeira conta.
    if auth.listar_usuarios() and not auth.usuario_da_sessao(session):
        raise HTTPException(status_code=401, detail="Sessão expirada ou inexistente. Faça login novamente.")

    try:
        usuario = auth.registrar(body.nome, body.email, body.senha)
    except auth.AuthError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    # Não loga automaticamente - evita trocar a sessão de quem já está
    # logado (o admin criando conta pra outra pessoa) pela da conta nova.
    return {"ok": True, **usuario}


@app.get("/api/auth/users")
def auth_users(_user: dict = Depends(require_auth)):
    return auth.listar_usuarios()


@app.post("/api/auth/login")
def auth_login(body: LoginBody, response: Response):
    try:
        usuario = auth.autenticar(body.email, body.senha)
    except auth.AuthError as exc:
        raise HTTPException(status_code=401, detail=str(exc))
    token = auth.criar_sessao(usuario["email"], usuario["nome"])
    _set_session_cookie(response, token)
    return {"ok": True, **usuario}


@app.post("/api/auth/logout")
def auth_logout(response: Response, session: Optional[str] = Cookie(None)):
    auth.destruir_sessao(session)
    response.delete_cookie(auth.SESSION_COOKIE_NAME)
    return {"ok": True}


@app.get("/api/auth/me")
def auth_me(session: Optional[str] = Cookie(None)):
    usuario = auth.usuario_da_sessao(session)
    if not usuario:
        raise HTTPException(status_code=401, detail="Não autenticado.")
    return {"ok": True, **usuario}


FIXTURE_FILES = {
    "fluxo_resumo": "fluxo_resumo.json",
    "fluxo_detalhe": "fluxo_detalhe.json",
    "pagar": "pagar.json",
    "receber": "receber.json",
    "pagar_resumo": "pagar_resumo.json",
    "receber_resumo": "receber_resumo.json",
    "historico": "historico.json",
}


def _load_fixture(key: str):
    path = FIXTURES_DIR / FIXTURE_FILES[key]
    if not path.exists():
        raise HTTPException(status_code=500, detail=f"Fixture não encontrada: {path.name}")
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _default_range() -> tuple[date, date]:
    ate = date.today()
    de = ate - timedelta(days=config.HANA_DEFAULT_DIAS - 1)
    return de, ate


def _resolve_range(de: Optional[date], ate: Optional[date]) -> tuple[date, date]:
    default_de, default_ate = _default_range()
    return (de or default_de), (ate or default_ate)


def _call_hana(fn, *args):
    import db  # import tardio: só exige hdbcli quando realmente em modo HANA

    try:
        return fn(*args)
    except db.HanaNotConfiguredError as exc:
        logger.error("HANA não configurado corretamente: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))
    except Exception:
        logger.exception("Falha ao consultar HANA (%s)", fn.__name__)
        raise HTTPException(
            status_code=502,
            detail=f"Falha ao consultar o HANA em '{fn.__name__}'. Ver logs do servidor.",
        )


@app.get("/api/health")
def health():
    return {"status": "ok", "config": config.hana_config_status()}


@app.get("/api/fluxo-resumo")
def fluxo_resumo(de: Optional[date] = Query(None), ate: Optional[date] = Query(None), _user: dict = Depends(require_auth)):
    if config.USE_FIXTURES:
        return _load_fixture("fluxo_resumo")
    import db
    d, a = _resolve_range(de, ate)
    return _call_hana(db.fetch_fluxo_resumo, d, a)


@app.get("/api/fluxo-detalhe")
def fluxo_detalhe(de: Optional[date] = Query(None), ate: Optional[date] = Query(None), _user: dict = Depends(require_auth)):
    if config.USE_FIXTURES:
        return _load_fixture("fluxo_detalhe")
    import db
    d, a = _resolve_range(de, ate)
    return _call_hana(db.fetch_fluxo_detalhe, d, a)


@app.get("/api/pagar")
def pagar(
    de: Optional[date] = Query(None),
    ate: Optional[date] = Query(None),
    corte: Optional[date] = Query(None),
    _user: dict = Depends(require_auth),
):
    if config.USE_FIXTURES:
        return _load_fixture("pagar")
    import db
    d, a = _resolve_range(de, ate)
    c = corte or a
    return _call_hana(db.fetch_pagar, d, a, c)


@app.get("/api/receber")
def receber(
    de: Optional[date] = Query(None),
    ate: Optional[date] = Query(None),
    corte: Optional[date] = Query(None),
    _user: dict = Depends(require_auth),
):
    if config.USE_FIXTURES:
        return _load_fixture("receber")
    import db
    d, a = _resolve_range(de, ate)
    c = corte or a
    return _call_hana(db.fetch_receber, d, a, c)


@app.get("/api/pagar-resumo")
def pagar_resumo(
    de: Optional[date] = Query(None),
    ate: Optional[date] = Query(None),
    corte: Optional[date] = Query(None),
    _user: dict = Depends(require_auth),
):
    if config.USE_FIXTURES:
        return _load_fixture("pagar_resumo")
    import db
    d, a = _resolve_range(de, ate)
    c = corte or a
    return _call_hana(db.fetch_pagar_resumo, d, a, c)


@app.get("/api/receber-resumo")
def receber_resumo(
    de: Optional[date] = Query(None),
    ate: Optional[date] = Query(None),
    corte: Optional[date] = Query(None),
    _user: dict = Depends(require_auth),
):
    if config.USE_FIXTURES:
        return _load_fixture("receber_resumo")
    import db
    d, a = _resolve_range(de, ate)
    c = corte or a
    return _call_hana(db.fetch_receber_resumo, d, a, c)


def _mes_atual_bounds() -> tuple[date, date, date]:
    hoje = date.today()
    ini = hoje.replace(day=1)
    fim = date(hoje.year, hoje.month, monthrange(hoje.year, hoje.month)[1])
    return ini, fim, hoje


def _mes_anterior_bounds(hoje: date) -> tuple[date, date, date]:
    ultimo_dia_mes_anterior = hoje.replace(day=1) - timedelta(days=1)
    ini = ultimo_dia_mes_anterior.replace(day=1)
    fim = ultimo_dia_mes_anterior
    dia_equivalente = min(hoje.day, ultimo_dia_mes_anterior.day)
    ate_equivalente = ini.replace(day=dia_equivalente)
    return ini, fim, ate_equivalente


@app.get("/api/historico")
def historico(_user: dict = Depends(require_auth)):
    """
    Comparação mês atual x mês anterior: disponibilidade, Pagar e Receber
    até o nível de fornecedor/cliente. Pensada pra leitura de diretoria -
    evolução, não só posição do momento.
    """
    if config.USE_FIXTURES:
        return _load_fixture("historico")

    import db

    ini_atual, fim_atual, hoje = _mes_atual_bounds()
    ini_anterior, fim_anterior, ate_anterior_equiv = _mes_anterior_bounds(hoje)

    try:
        pagar_comp = db.fetch_pagar_comparativo(
            ini_atual, fim_atual, ini_anterior, fim_anterior, fim_atual, fim_anterior
        )
        receber_comp = db.fetch_receber_comparativo(
            ini_atual, fim_atual, ini_anterior, fim_anterior, fim_atual, fim_anterior
        )
        disp_comp = db.fetch_disponibilidade_comparativa(
            ini_atual, hoje, ini_anterior, ate_anterior_equiv
        )
    except db.HanaNotConfiguredError as exc:
        logger.error("HANA não configurado corretamente: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))
    except Exception:
        logger.exception("Falha ao consultar HANA (historico)")
        raise HTTPException(
            status_code=502,
            detail="Falha ao consultar o HANA em 'historico'. Ver logs do servidor.",
        )

    return {
        "periodoAtual": {"de": ini_atual.isoformat(), "ate": fim_atual.isoformat()},
        "periodoAnterior": {"de": ini_anterior.isoformat(), "ate": fim_anterior.isoformat()},
        "disponibilidade": disp_comp,
        "pagar": pagar_comp,
        "receber": receber_comp,
    }


# Frontend estático (HTML/CSS/JS puro, sem build step)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/")
def index(session: Optional[str] = Cookie(None)):
    if not auth.usuario_da_sessao(session):
        return FileResponse(STATIC_DIR / "login.html")
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/login")
def login_page():
    return FileResponse(STATIC_DIR / "login.html")


@app.get("/usuarios")
def usuarios_page(session: Optional[str] = Cookie(None)):
    if not auth.usuario_da_sessao(session):
        return FileResponse(STATIC_DIR / "login.html")
    return FileResponse(STATIC_DIR / "usuarios.html")
