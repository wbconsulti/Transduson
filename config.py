"""
Configuração de ambiente do painel.

Tudo vem de variáveis de ambiente (.env em dev, variáveis reais no servidor
de integração do cliente). Nada de credencial hardcoded no código.
"""
import os


def _bool(name: str, default: bool) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


def _int(name: str, default: int) -> int:
    val = os.getenv(name)
    return int(val) if val else default


# Liga/desliga a fonte de dados: True = lê fixtures/*.json (v1 demo),
# False = conecta no HANA via hdbcli. Fica True por padrão de propósito -
# exige opt-in explícito pra falar com produção.
USE_FIXTURES = _bool("USE_FIXTURES", True)

# --- Conexão HANA (só usada quando USE_FIXTURES=false) ---------------------
HANA_HOST = os.getenv("HANA_HOST", "")
HANA_PORT = _int("HANA_PORT", 30015)
HANA_USER = os.getenv("HANA_USER", "")
HANA_PASSWORD = os.getenv("HANA_PASSWORD", "")
HANA_SCHEMA = os.getenv("HANA_SCHEMA", "SBO_TRANSDUSONPRD")
HANA_ENCRYPT = _bool("HANA_ENCRYPT", True)

# --- Table functions confirmadas com o cliente ------------------------------
# Fluxo de Caixa Resumo/Detalhe são table functions reais (recebem
# pDataIni/pDataFim como parâmetro de verdade). Pagar/Receber NÃO são
# objetos simples - são os scripts completos em sql/pagar_v12.sql e
# sql/receber_v1.sql (ver db.py).
HANA_TF_FLUXO_RESUMO = os.getenv("HANA_TF_FLUXO_RESUMO", "TF_FLUXO_CAIXA_RESUMIDO_DIARIO")
HANA_TF_FLUXO_DETALHE = os.getenv("HANA_TF_FLUXO_DETALHE", "TF_FLUXO_CAIXA_DETALHADO_DIARIO")

# Janela de datas padrão quando a API não recebe de/ate explícitos.
HANA_DEFAULT_DIAS = _int("HANA_DEFAULT_DIAS", 30)


def hana_config_status() -> dict:
    """Usado só pro /api/health - nunca devolve a senha."""
    return {
        "use_fixtures": USE_FIXTURES,
        "hana_host": HANA_HOST or None,
        "hana_port": HANA_PORT,
        "hana_schema": HANA_SCHEMA or None,
        "hana_user_set": bool(HANA_USER),
        "hana_password_set": bool(HANA_PASSWORD),
        "table_functions": {
            "fluxo_resumo": HANA_TF_FLUXO_RESUMO,
            "fluxo_detalhe": HANA_TF_FLUXO_DETALHE,
        },
        "pagar_sql": "sql/pagar_v12.sql",
        "receber_sql": "sql/receber_v1.sql",
        "default_dias": HANA_DEFAULT_DIAS,
    }
