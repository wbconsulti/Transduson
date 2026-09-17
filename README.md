# Painel de Fluxo de Caixa — Transduson (v1)

v1 de validação visual/UX. Todos os dados vêm de fixtures JSON locais
(`fixtures/*.json`) — **não há conexão com nenhum banco de dados real** e
nenhum driver de banco foi instalado.

## Rodando localmente

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload
```

Abra `http://localhost:8000` no navegador.

## Estrutura

```
main.py                  # FastAPI: 4 endpoints + serve o frontend estático
generate_fixtures.py     # gera fixtures/*.json (já rodado; rode de novo p/ variar os dados)
fixtures/
  fluxo_resumo.json       -> GET /api/fluxo-resumo
  fluxo_detalhe.json      -> GET /api/fluxo-detalhe
  pagar.json              -> GET /api/pagar
  receber.json            -> GET /api/receber
static/
  index.html              # shell com as 4 telas (nav lateral)
  css/style.css
  js/app.js               # fetch, tabelas, filtros, gráfico SVG feito à mão
```

## As 4 telas

1. **Resumo diário** — tabela por banco/dia + gráfico de linha (disponibilidade
   projetada, SVG feito à mão) com filtro por banco.
2. **Detalhe** — tabela por movimento, filtro por período e por CFO.
3. **Contas a pagar** — tabela por parcela, totalizador no topo, filtro por
   status, CFO e busca de fornecedor.
4. **Contas a receber** — espelho do pagar, para clientes.

Os valores da fixture de resumo diário batem com a soma da fixture de detalhe
do mesmo dia (gerado assim de propósito, para já sair no formato esperado
quando plugarmos no HANA depois).

## Editando os dados demo

Edite os JSON em `fixtures/` diretamente, ou ajuste `generate_fixtures.py` e
rode `python generate_fixtures.py` de novo para regenerar tudo (mantém a
mesma seed, então os números não mudam entre execuções a menos que o script
seja alterado).

## Conectando no HANA real

A fonte de dados é controlada pela variável `USE_FIXTURES` (arquivo `.env`,
veja `.env.example`). Schema confirmado: `SBO_TRANSDUSONPRD`.

**Resumo e Detalhe** são table functions reais no HANA — chamadas com bind
de parâmetro de verdade (`?`), sem concatenar string nenhuma:
- `TF_FLUXO_CAIXA_RESUMIDO_DIARIO(pDataIni, pDataFim)`
- `TF_FLUXO_CAIXA_DETALHADO_DIARIO(pDataIni, pDataFim)`

As colunas já saem com (ou são aliasadas para) os nomes exatos da fixture —
ver `_SQL_RESUMO`/`_SQL_DETALHE` em `db.py`.

**Pagar e Receber** não são views nem table functions — são os scripts
completos do SAP B1 Query Manager (recuperados da tabela `OUQR`), guardados
íntegros em `sql/pagar_v12.sql` (query "Financeiro V12") e
`sql/receber_v1.sql` (query "V1 RECEBER"). Como usam a sintaxe própria do
Query Manager (`DECLARE`, `:pDataIni`), `db.py`:
1. extrai só a parte executável (a partir do primeiro `WITH`, descartando o
   preâmbulo `DECLARE`/atribuição);
2. substitui `:pDataIni` / `:pDataFim` / `:pDataCorte` por literais de data
   — só aceita `datetime.date` de verdade, nunca texto cru, o que mantém
   isso seguro mesmo sem ser bind nativo;
3. remapeia as colunas "humanas" que voltam (`"Status Previsão"`,
   `"Nome Fornec"`, `"A PAGAR"`, o campo `_ord`...) para os nomes da
   fixture (`StatusPrevisao`, `NomeFornec`, `APagar`, `TipoLinha`...) — ver
   `_COLUMN_MAP_PAGAR` / `_COLUMN_MAP_RECEBER` em `db.py`.

Outras variações que existem no `OUQR` (`por CFO`, `com AGRUPAMENTOS V1`,
`Financeiro V11`) ficaram de fora por ora — a ideia é oferecê-las como
"modos de análise" alternativos no painel mais pra frente, mas a v1 usa só
a V12 (Pagar) e a V1 RECEBER (Receber) como fonte única de verdade.

Todos os 4 endpoints aceitam `de`/`ate` (e Pagar/Receber também `corte`) na
querystring, formato `YYYY-MM-DD`. Sem eles, usa uma janela padrão dos
últimos `HANA_DEFAULT_DIAS` dias (30 por padrão). Em modo fixtures esses
parâmetros são ignorados.

Passos para ligar no ambiente real do cliente:

1. `pip install -r requirements-hana.txt` (instala o `hdbcli`, separado do
   `requirements.txt` principal pra não obrigar esse binário em quem só
   quer rodar a demo).
2. Preencha no `.env`: `HANA_HOST`, `HANA_PORT`, `HANA_USER`,
   `HANA_PASSWORD` (schema e nomes das table functions já vêm certos por
   padrão).
3. `USE_FIXTURES=false` no `.env`.
4. Suba o servidor normalmente. Confira `GET /api/health` primeiro — mostra
   a config carregada (sem expor a senha) e os SQLs/table functions em uso.

Se a conexão ou a query falhar, a API responde com HTTP 502/500 e uma
mensagem no log do servidor — nunca expõe usuário/senha na resposta.

## Acesso (login)

O painel agora exige login — Nome, E-mail e Senha. Sem sessão válida,
qualquer rota (`/` e os endpoints `/api/*` de dado) devolve a tela de login
ou HTTP 401.

- Criação de conta é self-service: primeira vez, use a aba "Criar conta" na
  tela de login (`/login`).
- Senha nunca é salva em texto puro — hash PBKDF2-HMAC-SHA256 com salt
  aleatório por usuário (`hashlib`/`secrets` da biblioteca padrão, sem
  bcrypt/passlib), guardado em `data/users.json`.
- Sessão fica em memória (`auth.SESSIONS`) via cookie `session` — reiniciar
  o servidor derruba todo mundo logado. Se isso incomodar no dia a dia, dá
  pra persistir as sessões num arquivo depois.
- `data/users.json` não deve ser versionado/compartilhado — tem hash de
  senha de gente de verdade assim que alguém se cadastrar.

## Fora de escopo nesta v1

Login/autenticação real, deploy no servidor do cliente, e o assistente de
perguntas em linguagem natural — ver `PROMPT-V1-APP.md` do cliente para o
detalhamento original. A conexão com o HANA (acima) já está pronta e
mapeada; falta só rodar contra o ambiente real do cliente pra validar
volume de dados e performance das queries de Pagar/Receber (são scripts
bem pesados, com várias CTEs).
