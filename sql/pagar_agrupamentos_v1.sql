/* SELECT FROM OJDT X10 */

DECLARE pDataIni DATE;
DECLARE pDataFim DATE;
DECLARE pDataCorte DATE;

pDataIni := /* X10."RefDate" as "Data Inicio" */ '[%0]' ;
pDataFim := /* X10."RefDate" as "Data Final" */ '[%1]' ;
pDataCorte := /* X10."RefDate" as "Data Corte" */ '[%2]' ;

WITH DadosBase AS
(
    SELECT *
    FROM "VW_FLUXO_PREVPEDIDO"
    WHERE "Vencimento" BETWEEN :pDataIni AND :pDataFim
),

DadosNota AS
(
    SELECT *
    FROM "VW_FLUXO_NFENTRPARC"
    WHERE 
        "CreateDateNF" <= :pDataCorte
        AND "Vencimento" BETWEEN :pDataIni AND :pDataFim
),

DadosPag AS
(
    SELECT *
    FROM "VW_FLUXO_PAGAMENTOS"
    WHERE 
        "TrsfrDate" BETWEEN :pDataIni AND :pDataFim
),

Detalhe AS
(
    SELECT
        COALESCE(B."Ano", N."Ano", YEAR(PG."TrsfrDate")) AS "Ano",
        COALESCE(B."MesNum", N."MesNum", MONTH(PG."TrsfrDate")) AS "MesNum",
        COALESCE(B."Vencimento", N."Vencimento", PG."TrsfrDate") AS "Vencimento",
        COALESCE(B."Status Previsão", N."Status Previsão", 'FORA FLUXO') AS "Status Previsão",
        COALESCE(B."CardCode", N."CardCode", PG."CardCode") AS "Cod.Fornec",
        COALESCE(B."CardName", N."CardName", PG."NomeCredor") AS "Nome Fornec",
        COALESCE(B."CFO", N."CFO", PG."CFO") AS "CFO",
        COALESCE(B."Nome CFO", N."Nome CFO") AS "Nome CFO",
        COALESCE(B."Tipo CFO", N."Tipo CFO") AS "Tipo CFO",
        COALESCE(B."Raiz CFO", N."Raiz CFO") AS "Raiz CFO",
        COALESCE(B."CCusto", N."CCusto") AS "CCusto",
        COALESCE(B."Nome CCusto", N."Nome CCusto") AS "Nome CCusto",

        CAST(SUM(COALESCE(B."Valor Ano", 0)) AS DECIMAL(19,6)) AS "Valor Ano",
        Case When COALESCE(B."Status Previsão", N."Status Previsão", 'FORA FLUXO') = 'NÃO PAGAR' Then 0 Else
        CAST(CASE WHEN COALESCE(B."Valor Mes", 0) = 0 THEN COALESCE(B."Valor Ano", N."Valor Mes", 0) ELSE COALESCE(B."Valor Mes", N."Valor Mes", 0) END AS DECIMAL(19,6)) End AS "Valor Mes Original",
        CAST(COALESCE(N."Valor Variavel", B."Valor Variavel", 0) AS DECIMAL(19,6)) AS "Valor Variavel",
        CAST(SUM(COALESCE(N."Lancado (NF)", 0)) AS DECIMAL(19,6)) AS "Lancado (NF)",
        CAST(COALESCE(N."Lancado (NF)", B."Valor Variavel", N."Valor Variavel", 0) AS DECIMAL(19,6)) AS "A PAGAR",
        CAST(SUM(COALESCE(PG."Pago", 0)) AS DECIMAL(19,6)) AS "Pago",
        PG."TrsfrDate" AS "Data Pagto",
        N."Parcela",
        CAST(CASE WHEN COALESCE(PG."Pago", 0) <> 0 THEN SUM(COALESCE(PG."Pago", 0)) - SUM(COALESCE(B."Valor Mes", N."Lancado (NF)", 0)) ELSE 0 END AS DECIMAL(19,6)) AS "Var Realiz",
        B."DocNumPed", B."LinhaPed", B."Usage", N."Centro Custo", N."Class.Financ.", N."DocNumSAP", PG."InvType", PG."ContaPagamento",
        COALESCE(N."Comments", B."Comments") AS "Comments",
        COALESCE(N."CreateDateNF", B."CreateDatePed") AS "CreateDate"
    FROM DadosBase B
    FULL OUTER JOIN DadosNota N ON B."DocEntryPed" = N."BaseRefPed" AND B."LinhaPed" = N."BaseLinePed"
    FULL OUTER JOIN DadosPag PG ON N."DocEntryNF" = PG."DocEntryNF" AND N."Parcela" = PG."Parcela"
    GROUP BY
        B."Ano", N."Ano", PG."TrsfrDate", B."MesNum", N."MesNum", B."Vencimento", N."Vencimento", B."Status Previsão", N."Status Previsão",
        B."CardCode", N."CardCode", PG."CardCode", B."CardName", N."CardName", PG."NomeCredor", B."CFO", N."CFO", PG."CFO", B."Nome CFO", N."Nome CFO",
        B."Tipo CFO", N."Tipo CFO", B."Raiz CFO", N."Raiz CFO", B."CCusto", N."CCusto", B."Nome CCusto", N."Nome CCusto", B."Valor Ano", B."Valor Mes", N."Valor Mes",
        B."Valor Variavel", N."Valor Variavel", N."Lancado (NF)", PG."Pago", N."Parcela", B."DocNumPed", B."LinhaPed", B."Usage", N."Centro Custo", N."Class.Financ.",
        N."DocNumSAP", PG."InvType", PG."ContaPagamento", N."Comments", B."Comments", N."CreateDateNF", B."CreateDatePed"
),

Resultado AS
(
    SELECT
        "Ano", "MesNum", "Cod.Fornec", "Nome Fornec", "Vencimento", "Status Previsão", "Valor Ano",
        CAST(CASE WHEN "Status Previsão" = 'PREVISTO' AND "CreateDate" <= :pDataCorte THEN "Lancado (NF)" ELSE "Valor Mes Original" END AS DECIMAL(19,6)) AS "Valor Mes",
        "Valor Variavel", "Lancado (NF)", "A PAGAR", "Pago", "Data Pagto", "Parcela", "Var Realiz",
        "CFO", "Nome CFO", "Tipo CFO", "Raiz CFO", "CCusto", "Nome CCusto", "DocNumPed", "LinhaPed", "Usage",
        "Centro Custo", "Class.Financ.", "DocNumSAP", "InvType", "ContaPagamento", "Comments"
    FROM Detalhe
)

-- ===================================================================
-- 1. RESUMO: TOTAL GERAL
-- ===================================================================
SELECT
    10 AS "_ord", 'Geral' AS "Agrupamento", CAST(NULL AS INTEGER) AS "Ano", CAST(NULL AS INTEGER) AS "MesNum", CAST(NULL AS DATE) AS "Vencimento", CAST('TOTAL' AS NVARCHAR(50)) AS "Status Previsão", CAST(NULL AS NVARCHAR(30)) AS "Cod.Fornec",
    CAST('TOTAL GERAL' AS NVARCHAR(200)) AS "Nome Fornec",
    CAST(SUM("Valor Ano") AS DECIMAL(19,6)) AS "Valor Ano", CAST(SUM(CASE WHEN COALESCE("Valor Mes", 0) = 0 THEN COALESCE("Valor Variavel", 0) ELSE COALESCE("Valor Mes", 0) END) AS DECIMAL(19,6)) AS "Valor Mes", CAST(SUM("Valor Variavel") AS DECIMAL(19,6)) AS "Valor Variavel", CAST(SUM("Lancado (NF)") AS DECIMAL(19,6)) AS "Lancado (NF)", CAST(SUM("A PAGAR") AS DECIMAL(19,6)) AS "A PAGAR", CAST(SUM("Pago") AS DECIMAL(19,6)) AS "Pago", CAST(SUM("Var Realiz") AS DECIMAL(19,6)) AS "Var Realiz"
FROM Resultado

UNION ALL

-- SEPARADOR STATUS
SELECT 19, 'Status Previsão', NULL, NULL, NULL, NULL, NULL, CAST('---------------------------------------- RESUMO: STATUS DA PREVISÃO ----------------------------------------' AS NVARCHAR(200)), NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM DUMMY
UNION ALL

-- 2. RESUMO POR: STATUS DA PREVISÃO
SELECT
    20 AS "_ord", 'Status Previsão' AS "Agrupamento", CAST(NULL AS INTEGER), CAST(NULL AS INTEGER), CAST(NULL AS DATE), CAST("Status Previsão" AS NVARCHAR(50)), CAST(NULL AS NVARCHAR(30)),
    CAST("Status Previsão" AS NVARCHAR(200)),
    CAST(SUM("Valor Ano") AS DECIMAL(19,6)), CAST(SUM(CASE WHEN COALESCE("Valor Mes", 0) = 0 THEN COALESCE("Valor Variavel", 0) ELSE COALESCE("Valor Mes", 0) END) AS DECIMAL(19,6)), CAST(SUM("Valor Variavel") AS DECIMAL(19,6)), CAST(SUM("Lancado (NF)") AS DECIMAL(19,6)), CAST(SUM("A PAGAR") AS DECIMAL(19,6)), CAST(SUM("Pago") AS DECIMAL(19,6)), CAST(SUM("Var Realiz") AS DECIMAL(19,6))
FROM Resultado GROUP BY "Status Previsão"

UNION ALL

-- SEPARADOR VENCIMENTO
SELECT 29, 'Data Vencimento', NULL, NULL, NULL, NULL, NULL, CAST('---------------------------------------- RESUMO: DATA DE VENCIMENTO ----------------------------------------' AS NVARCHAR(200)), NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM DUMMY
UNION ALL

-- 3. RESUMO POR: DATA DE VENCIMENTO
SELECT
    30 AS "_ord", 'Data Vencimento' AS "Agrupamento", CAST(NULL AS INTEGER), CAST(NULL AS INTEGER), "Vencimento", CAST('RESUMO VENC.' AS NVARCHAR(50)), CAST(NULL AS NVARCHAR(30)),
    CAST(TO_VARCHAR("Vencimento", 'DD/MM/YYYY') AS NVARCHAR(200)),
    CAST(SUM("Valor Ano") AS DECIMAL(19,6)), CAST(SUM(CASE WHEN COALESCE("Valor Mes", 0) = 0 THEN COALESCE("Valor Variavel", 0) ELSE COALESCE("Valor Mes", 0) END) AS DECIMAL(19,6)), CAST(SUM("Valor Variavel") AS DECIMAL(19,6)), CAST(SUM("Lancado (NF)") AS DECIMAL(19,6)), CAST(SUM("A PAGAR") AS DECIMAL(19,6)), CAST(SUM("Pago") AS DECIMAL(19,6)), CAST(SUM("Var Realiz") AS DECIMAL(19,6))
FROM Resultado GROUP BY "Vencimento"

UNION ALL

-- SEPARADOR NOME CFO
SELECT 39, 'Nome CFO', NULL, NULL, NULL, NULL, NULL, CAST('---------------------------------------- RESUMO: NOME CFO ----------------------------------------' AS NVARCHAR(200)), NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM DUMMY
UNION ALL

-- 4. RESUMO POR: NOME CFO
SELECT
    40 AS "_ord", 'Nome CFO' AS "Agrupamento", CAST(NULL AS INTEGER), CAST(NULL AS INTEGER), CAST(NULL AS DATE), CAST(NULL AS NVARCHAR(50)), CAST(NULL AS NVARCHAR(30)),
    CAST(COALESCE("Nome CFO", 'NÃO INFORMADO') AS NVARCHAR(200)),
    CAST(SUM("Valor Ano") AS DECIMAL(19,6)), CAST(SUM(CASE WHEN COALESCE("Valor Mes", 0) = 0 THEN COALESCE("Valor Variavel", 0) ELSE COALESCE("Valor Mes", 0) END) AS DECIMAL(19,6)), CAST(SUM("Valor Variavel") AS DECIMAL(19,6)), CAST(SUM("Lancado (NF)") AS DECIMAL(19,6)), CAST(SUM("A PAGAR") AS DECIMAL(19,6)), CAST(SUM("Pago") AS DECIMAL(19,6)), CAST(SUM("Var Realiz") AS DECIMAL(19,6))
FROM Resultado GROUP BY "Nome CFO"

UNION ALL

-- SEPARADOR RAIZ CFO
SELECT 49, 'Raiz CFO', NULL, NULL, NULL, NULL, NULL, CAST('---------------------------------------- RESUMO: RAIZ CFO ----------------------------------------' AS NVARCHAR(200)), NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM DUMMY
UNION ALL

-- 5. RESUMO POR: RAIZ CFO
SELECT
    50 AS "_ord", 'Raiz CFO' AS "Agrupamento", CAST(NULL AS INTEGER), CAST(NULL AS INTEGER), CAST(NULL AS DATE), CAST(NULL AS NVARCHAR(50)), CAST(NULL AS NVARCHAR(30)),
    CAST(COALESCE("Raiz CFO", 'NÃO INFORMADO') AS NVARCHAR(200)),
    CAST(SUM("Valor Ano") AS DECIMAL(19,6)), CAST(SUM(CASE WHEN COALESCE("Valor Mes", 0) = 0 THEN COALESCE("Valor Variavel", 0) ELSE COALESCE("Valor Mes", 0) END) AS DECIMAL(19,6)), CAST(SUM("Valor Variavel") AS DECIMAL(19,6)), CAST(SUM("Lancado (NF)") AS DECIMAL(19,6)), CAST(SUM("A PAGAR") AS DECIMAL(19,6)), CAST(SUM("Pago") AS DECIMAL(19,6)), CAST(SUM("Var Realiz") AS DECIMAL(19,6))
FROM Resultado GROUP BY "Raiz CFO"

UNION ALL

-- SEPARADOR TIPO CFO
SELECT 59, 'Tipo CFO', NULL, NULL, NULL, NULL, NULL, CAST('---------------------------------------- RESUMO: TIPO CFO ----------------------------------------' AS NVARCHAR(200)), NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM DUMMY
UNION ALL

-- 6. RESUMO POR: TIPO CFO
SELECT
    60 AS "_ord", 'Tipo CFO' AS "Agrupamento", CAST(NULL AS INTEGER), CAST(NULL AS INTEGER), CAST(NULL AS DATE), CAST(NULL AS NVARCHAR(50)), CAST(NULL AS NVARCHAR(30)),
    CAST(COALESCE("Tipo CFO", 'NÃO INFORMADO') AS NVARCHAR(200)),
    CAST(SUM("Valor Ano") AS DECIMAL(19,6)), CAST(SUM(CASE WHEN COALESCE("Valor Mes", 0) = 0 THEN COALESCE("Valor Variavel", 0) ELSE COALESCE("Valor Mes", 0) END) AS DECIMAL(19,6)), CAST(SUM("Valor Variavel") AS DECIMAL(19,6)), CAST(SUM("Lancado (NF)") AS DECIMAL(19,6)), CAST(SUM("A PAGAR") AS DECIMAL(19,6)), CAST(SUM("Pago") AS DECIMAL(19,6)), CAST(SUM("Var Realiz") AS DECIMAL(19,6))
FROM Resultado GROUP BY "Tipo CFO"

UNION ALL

-- SEPARADOR CENTRO DE CUSTO
SELECT 69, 'Centro de Custo', NULL, NULL, NULL, NULL, NULL, CAST('---------------------------------------- RESUMO: CENTRO DE CUSTO ----------------------------------------' AS NVARCHAR(200)), NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM DUMMY
UNION ALL

-- 7. RESUMO POR: NOME CENTRO DE CUSTO
SELECT
    70 AS "_ord", 'Centro de Custo' AS "Agrupamento", CAST(NULL AS INTEGER), CAST(NULL AS INTEGER), CAST(NULL AS DATE), CAST(NULL AS NVARCHAR(50)), CAST(NULL AS NVARCHAR(30)),
    CAST(COALESCE("Nome CCusto", 'NÃO INFORMADO') AS NVARCHAR(200)),
    CAST(SUM("Valor Ano") AS DECIMAL(19,6)), CAST(SUM(CASE WHEN COALESCE("Valor Mes", 0) = 0 THEN COALESCE("Valor Variavel", 0) ELSE COALESCE("Valor Mes", 0) END) AS DECIMAL(19,6)), CAST(SUM("Valor Variavel") AS DECIMAL(19,6)), CAST(SUM("Lancado (NF)") AS DECIMAL(19,6)), CAST(SUM("A PAGAR") AS DECIMAL(19,6)), CAST(SUM("Pago") AS DECIMAL(19,6)), CAST(SUM("Var Realiz") AS DECIMAL(19,6))
FROM Resultado GROUP BY "Nome CCusto"

ORDER BY 
    "_ord" ASC, 
    "Nome Fornec" ASC;
