"""
Autenticação simples por usuário/senha - Nome, Email, Senha.

Guarda os usuários num JSON local (data/users.json). Senha nunca é salva
em texto puro - só hash PBKDF2-HMAC-SHA256 com salt aleatório por usuário,
usando somente `hashlib`/`secrets` da biblioteca padrão (sem bcrypt/passlib,
por decisão de manter a stack sem dependência de binário compilado).

Sessão: token aleatório guardado num dict em memória (SESSIONS). Reiniciar
o servidor derruba todo mundo - aceitável pra essa fase; se isso incomodar
no dia a dia, dá pra persistir SESSIONS num arquivo depois.
"""
import hashlib
import json
import re
import secrets
from pathlib import Path
from typing import Optional

DATA_DIR = Path(__file__).resolve().parent / "data"
USERS_FILE = DATA_DIR / "users.json"

PBKDF2_ITERATIONS = 200_000
SESSION_COOKIE_NAME = "session"
SESSION_TTL_HOURS = 12

# token -> {"email": str, "criado_em": iso str}
SESSIONS: dict[str, dict] = {}

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class AuthError(Exception):
    pass


def _load_users() -> list[dict]:
    if not USERS_FILE.exists():
        return []
    with open(USERS_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def _save_users(users: list[dict]) -> None:
    DATA_DIR.mkdir(exist_ok=True)
    with open(USERS_FILE, "w", encoding="utf-8") as f:
        json.dump(users, f, ensure_ascii=False, indent=2)


def _hash_password(senha: str, salt: Optional[bytes] = None) -> tuple[str, str]:
    if salt is None:
        salt = secrets.token_bytes(16)
    hash_bytes = hashlib.pbkdf2_hmac("sha256", senha.encode("utf-8"), salt, PBKDF2_ITERATIONS)
    return salt.hex(), hash_bytes.hex()


def _verify_password(senha: str, salt_hex: str, hash_hex: str) -> bool:
    salt = bytes.fromhex(salt_hex)
    _, computed_hex = _hash_password(senha, salt)
    return secrets.compare_digest(computed_hex, hash_hex)


def registrar(nome: str, email: str, senha: str) -> dict:
    nome = (nome or "").strip()
    email = (email or "").strip().lower()
    senha = senha or ""

    if not nome:
        raise AuthError("Informe o nome.")
    if not EMAIL_RE.match(email):
        raise AuthError("E-mail inválido.")
    if len(senha) < 6:
        raise AuthError("A senha precisa ter pelo menos 6 caracteres.")

    users = _load_users()
    if any(u["email"] == email for u in users):
        raise AuthError("Já existe uma conta com esse e-mail.")

    salt_hex, hash_hex = _hash_password(senha)
    novo = {"nome": nome, "email": email, "salt": salt_hex, "hash": hash_hex}
    users.append(novo)
    _save_users(users)
    return {"nome": nome, "email": email}


def autenticar(email: str, senha: str) -> dict:
    email = (email or "").strip().lower()
    users = _load_users()
    user = next((u for u in users if u["email"] == email), None)
    if not user or not _verify_password(senha or "", user["salt"], user["hash"]):
        raise AuthError("E-mail ou senha incorretos.")
    return {"nome": user["nome"], "email": user["email"]}


def criar_sessao(email: str, nome: str) -> str:
    token = secrets.token_urlsafe(32)
    SESSIONS[token] = {"email": email, "nome": nome}
    return token


def usuario_da_sessao(token: Optional[str]) -> Optional[dict]:
    if not token:
        return None
    return SESSIONS.get(token)


def destruir_sessao(token: Optional[str]) -> None:
    if token:
        SESSIONS.pop(token, None)


def listar_usuarios() -> list[dict]:
    """Nunca devolve salt/hash - só o que é seguro mostrar na tela."""
    return [{"nome": u["nome"], "email": u["email"]} for u in _load_users()]
