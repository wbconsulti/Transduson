/* SELECT FROM OJDT X10 */

Declare pDataIni Date;
Declare pDataFim Date;
Declare pDataCorte Date;


pDataIni := /* X10."RefDate" as "Data Inicio" */ '[%0]' ;
pDataFim := /* X10."RefDate" as "Data Final" */ '[%1]' ;
pDataCorte := /* X10."RefDate" as "Data Corte" */ '[%2]' ;

    -- 1. PEDIDOS JA RECEBIDOS POR FATURA DE ADIANTAMENTO
    --    DPI1 liga o adiantamento ao pedido de venda (BaseType = 17).
    --    RCT2 confirma que houve valor efetivamente recebido (InvType = 203).
    WITH VinculoAdiantamentoPedido AS
    (
        SELECT DISTINCT
            D1."BaseEntry" AS "DocEntryPed",
            D0."DocEntry"  AS "DocEntryAdiantamento"
        FROM DPI1 D1
        INNER JOIN ODPI D0
            ON D0."DocEntry" = D1."DocEntry"
        WHERE D1."BaseType" = 17
          AND D0."CANCELED" = 'N'
    ),

    RecebimentoAdiantamentoPedido AS
    (
        SELECT
            VA."DocEntryPed",
            SUM(COALESCE(PR."SumApplied", 0)) AS "ValorRecebido"
        FROM VinculoAdiantamentoPedido VA
        INNER JOIN RCT2 PR
            ON PR."DocEntry" = VA."DocEntryAdiantamento"
           AND PR."InvType" = '203'
           AND COALESCE(PR."SumApplied", 0) > 0.000001
        INNER JOIN ORCT R0
            ON R0."DocEntry" = PR."DocNum"
           AND R0."Canceled" = 'N'
        WHERE COALESCE(R0."TrsfrDate", R0."DocDate") <= :pDataCorte
        GROUP BY VA."DocEntryPed"
    ),

    PedidosRecebidosAdiantamento AS
    (
        SELECT RA."DocEntryPed"
        FROM RecebimentoAdiantamentoPedido RA
        INNER JOIN ORDR PV
            ON PV."DocEntry" = RA."DocEntryPed"
        WHERE RA."ValorRecebido" >= COALESCE(PV."DocTotal", 0) - 0.01
    ),

    -- 2. BASE EFETIVA DE PEDIDOS (Previsto)
    DadosBase AS
    (
        SELECT 
            "DocEntryPed",
            "LinhaPed",
            "DocNumPed",
            "Ano",
            "MesNum",
            "Vencimento",
            "Status Previsão",
            "CardCode",
            "CardName",
            "CFO",
            "Nome CFO",
            "Tipo CFO",
            "Raiz CFO",
            "CCusto",
            "Nome CCusto",
            "Usage",
            "Comments",
            "CreateDatePed",
            SUM(COALESCE("Valor Ano", 0))       AS "Valor Ano",
            SUM(COALESCE("Valor Mes", 0))       AS "Valor Mes",
            SUM(COALESCE("Valor Variavel", 0))  AS "Valor Variavel"
        FROM "VW_FLUXO_PREVVENDA" PV
        WHERE PV."Vencimento" BETWEEN :pDataIni AND :pDataFim
          AND NOT EXISTS
          (
              SELECT 1
              FROM PedidosRecebidosAdiantamento PA
              WHERE PA."DocEntryPed" = PV."DocEntryPed"
          )
        GROUP BY
            "DocEntryPed",
            "LinhaPed",
            "DocNumPed",
            "Ano",
            "MesNum",
            "Vencimento",
            "Status Previsão",
            "CardCode",
            "CardName",
            "CFO",
            "Nome CFO",
            "Tipo CFO",
            "Raiz CFO",
            "CCusto",
            "Nome CCusto",
            "Usage",
            "Comments",
            "CreateDatePed"
    ),

    -- 2. BUSCA AS LINHAS REAIS DA NOTA (Correção da perda do BaseRefPed da NFLINEPICK)
    VinculoNotaPedido AS
    (
        SELECT
            X."DocEntry",
            X."BaseRefPed",
            X."BaseLinePed"
        FROM
        (
            SELECT
                I."DocEntry",
                CASE
                    WHEN I."BaseType" = 17 THEN I."BaseEntry"
                    WHEN I."BaseType" = 15 AND D."BaseType" = 17 THEN D."BaseEntry"
                    ELSE NULL
                END AS "BaseRefPed",
                CASE
                    WHEN I."BaseType" = 17 THEN I."BaseLine"
                    WHEN I."BaseType" = 15 AND D."BaseType" = 17 THEN D."BaseLine"
                    ELSE NULL
                END AS "BaseLinePed",
                ROW_NUMBER() OVER
                (
                    PARTITION BY I."DocEntry"
                    ORDER BY
                        CASE
                            WHEN I."BaseType" = 17 THEN 0
                            WHEN I."BaseType" = 15 AND D."BaseType" = 17 THEN 1
                            ELSE 2
                        END,
                        I."LineNum"
                ) AS "rn"
            FROM INV1 I
            LEFT JOIN DLN1 D
                ON I."BaseType" = 15
               AND D."DocEntry" = I."BaseEntry"
               AND D."LineNum" = I."BaseLine"
        ) X
        WHERE X."rn" = 1
    ),

    -- 3. NOTAS FISCAIS PARCELADAS (Desduplicadas)
    DadosNotaConsolidada AS
    (
        SELECT 
            NF."DocEntryNF",
            NF."Parcela",
            NF."Ano",
            NF."MesNum",
            NF."Vencimento",
            NF."Status Previsão",
            NF."CardCode",
            NF."CardName",
            NF."CFO",
            NF."Nome CFO",
            NF."Tipo CFO",
            NF."Raiz CFO",
            NF."CCusto",
            NF."Nome CCusto",
            NF."Centro Custo",
            NF."Class.Financ.",
            NF."DocNumSAP",
            NF."Comments",
            NF."CreateDateNF",
            MAX(COALESCE(SP."Status", 'O')) AS "Status Parcela SAP",
            MAX(COALESCE(SP."InsTotal", 0)) AS "Valor Parcela SAP",
            MAX(COALESCE(SP."PaidToDate", 0)) AS "Recebido Parcela SAP",
            
            -- Usa o vinculo resolvido da INV1, inclusive quando a NF veio por entrega.
            COALESCE(V."BaseRefPed", NF."BaseRefPed")  AS "BaseRefPed",
            COALESCE(V."BaseLinePed", NF."BaseLinePed") AS "BaseLinePed",

            -- MAX evita duplicacao dos valores consolidados na view parcelada.
            MAX(COALESCE(NF."Valor Ano", 0))       AS "Valor Ano NF",
            MAX(COALESCE(NF."Valor Mes", 0))       AS "Valor Mes NF",
            MAX(COALESCE(NF."Valor Variavel", 0))  AS "Valor Variavel NF",
            MAX(COALESCE(NF."ImpRet", 0))          AS "ImpRet",
            MAX(COALESCE(NF."Lancado (NF)", 0))    AS "Lancado (NF)"
        FROM "VW_FLUXO_NFSAIDAPARC" NF
        LEFT JOIN VinculoNotaPedido V ON V."DocEntry" = NF."DocEntryNF"
        INNER JOIN INV6 SP
            ON SP."DocEntry" = NF."DocEntryNF"
           AND SP."InstlmntID" = NF."Parcela"
        WHERE 
            NF."CreateDateNF" <= :pDataCorte
            AND NF."Vencimento" BETWEEN :pDataIni AND :pDataFim
        GROUP BY
            NF."DocEntryNF",
            NF."Parcela",
            NF."Ano",
            NF."MesNum",
            NF."Vencimento",
            NF."Status Previsão",
            NF."CardCode",
            NF."CardName",
            NF."CFO",
            NF."Nome CFO",
            NF."Tipo CFO",
            NF."Raiz CFO",
            NF."CCusto",
            NF."Nome CCusto",
            NF."Centro Custo",
            NF."Class.Financ.",
            NF."DocNumSAP",
            NF."Comments",
            NF."CreateDateNF",
            COALESCE(V."BaseRefPed", NF."BaseRefPed"),
            COALESCE(V."BaseLinePed", NF."BaseLinePed")
    ),

    -- 4. RECEBIMENTOS REALIZADOS
    DadosRec AS
    (
        SELECT
            R."DocEntryNF",
            R."Parcela",
            R."CardCode",
            R."NomeCliente",
            R."CFO",
            R."InvType",
            R."ContaRecebimento",
            MAX(R."TrsfrDate") AS "TrsfrDate",
            SUM(COALESCE(R."Recebido", 0)) AS "Recebido"
        FROM "VW_FLUXO_RECEBIMENTOS" R
        WHERE R."TrsfrDate" BETWEEN :pDataIni AND :pDataFim
        GROUP BY
            R."DocEntryNF",
            R."Parcela",
            R."CardCode",
            R."NomeCliente",
            R."CFO",
            R."InvType",
            R."ContaRecebimento"
    ),

    -- 5. SALDO DIARIO A RECEBER DO CARTAO:
    --    SOMENTE DEBITOS DA CONTA CONTABIL, PELO DueDate DA JDT1.
    DadosCartao AS
    (
        SELECT
            YEAR(L."DueDate") AS "Ano",
            MONTH(L."DueDate") AS "MesNum",
            L."DueDate" AS "Vencimento",
            CAST('CARTAO' AS NVARCHAR(50)) AS "Status Previsão",
            CAST('CARTAO' AS NVARCHAR(30)) AS "Cod.Cliente",
            CAST(COALESCE(AC."AcctName", 'CARTAO DE CREDITO') AS NVARCHAR(200)) AS "Nome Cliente",
            CAST(NULL AS NVARCHAR(30)) AS "CFO",
            CAST(NULL AS NVARCHAR(200)) AS "Nome CFO",
            CAST(NULL AS NVARCHAR(30)) AS "Tipo CFO",
            CAST(NULL AS NVARCHAR(30)) AS "Raiz CFO",
            CAST(NULL AS NVARCHAR(30)) AS "CCusto",
            CAST(NULL AS NVARCHAR(200)) AS "Nome CCusto",
            CAST(0 AS DECIMAL(19,6)) AS "Valor Ano",
            CAST(SUM(COALESCE(L."Debit", 0)) AS DECIMAL(19,6)) AS "Valor Mes",
            CAST(SUM(COALESCE(L."Debit", 0)) AS DECIMAL(19,6)) AS "Valor Variavel",
            CAST(0 AS DECIMAL(19,6)) AS "ImpRet",
            CAST(0 AS DECIMAL(19,6)) AS "Lancado (NF)",
            CAST(SUM(COALESCE(L."Debit", 0)) AS DECIMAL(19,6)) AS "A RECEBER",
            CAST(0 AS DECIMAL(19,6)) AS "Recebido",
            CAST(NULL AS DATE) AS "Data Receb.",
            CAST(NULL AS INTEGER) AS "Parcela",
            CAST(0 AS DECIMAL(19,6)) AS "Var Realiz",
            CAST(NULL AS INTEGER) AS "DocNumPed",
            CAST(NULL AS INTEGER) AS "LinhaPed",
            CAST(NULL AS INTEGER) AS "Usage",
            CAST(NULL AS NVARCHAR(30)) AS "Centro Custo",
            CAST(NULL AS NVARCHAR(30)) AS "Class.Financ.",
            CAST(NULL AS INTEGER) AS "DocNumSAP",
            CAST('30' AS NVARCHAR(20)) AS "InvType",
            CAST(
                COALESCE(AC."FormatCode", AC."AcctCode", L."Account")
                || ' - '
                || COALESCE(AC."AcctName", 'CARTAO DE CREDITO')
                AS NVARCHAR(200)
            ) AS "ContaRecebimento",
            CAST('SALDO DIARIO DA CONTA DE CARTAO' AS NVARCHAR(254)) AS "Comments"
        FROM JDT1 L
        INNER JOIN OJDT H
            ON H."TransId" = L."TransId"
        LEFT JOIN OACT AC
            ON AC."AcctCode" = L."Account"
        WHERE (
                L."Account" = '1.01.03.04.01'
                OR AC."FormatCode" = '1.01.03.04.01'
              )
          AND L."DueDate" BETWEEN :pDataIni AND :pDataFim
          AND H."RefDate" <= :pDataCorte
          AND COALESCE(L."Debit", 0) > 0.000001
        GROUP BY
            L."DueDate",
            AC."FormatCode",
            AC."AcctCode",
            AC."AcctName",
            L."Account"
        HAVING SUM(COALESCE(L."Debit", 0)) > 0.000001
    ),

    -- 5. UNIFICAÇÃO DOS DADOS
    DetalheOperacional AS
    (
        SELECT
            COALESCE(B."Ano", N."Ano", YEAR(RC."TrsfrDate")) AS "Ano",
            COALESCE(B."MesNum", N."MesNum", MONTH(RC."TrsfrDate")) AS "MesNum",
            COALESCE(B."Vencimento", N."Vencimento", RC."TrsfrDate") AS "Vencimento",

            COALESCE(B."Status Previsão", N."Status Previsão", 'SEM PREVISÃO') AS "Status Previsão",

            COALESCE(B."CardCode", N."CardCode", RC."CardCode") AS "Cod.Cliente",
            COALESCE(B."CardName", N."CardName", RC."NomeCliente") AS "Nome Cliente",

            COALESCE(B."CFO", N."CFO", RC."CFO") AS "CFO",
            COALESCE(B."Nome CFO", N."Nome CFO") AS "Nome CFO",
            COALESCE(B."Tipo CFO", N."Tipo CFO") AS "Tipo CFO",
            COALESCE(B."Raiz CFO", N."Raiz CFO") AS "Raiz CFO",

            COALESCE(B."CCusto", N."CCusto") AS "CCusto",
            COALESCE(B."Nome CCusto", N."Nome CCusto") AS "Nome CCusto",

            -- Valor Ano: PRESERVAÇÃO TOTAL da DadosBase (Regra 1). Se veio só Nota sem Pedido, usa o da Nota.
            CAST(COALESCE(B."Valor Ano", N."Valor Ano NF", 0) AS DECIMAL(19,6)) AS "Valor Ano",

            -- Valor Mes: usa o pedido enquanto nao houver NF; existindo NF, usa o valor da NF.
            -- O teste e feito pelo DocEntryNF (e nao pelo valor), pois uma NF de valor zero
            -- continua sendo uma NF lancada e nao deve reativar o valor previsto do pedido.
            CAST(
                CASE
                    WHEN N."DocEntryNF" IS NOT NULL
                        THEN COALESCE(N."Valor Mes NF", 0)
                    ELSE COALESCE(B."Valor Mes", 0)
                END
            AS DECIMAL(19,6)) AS "Valor Mes",

            -- Valor Variavel:
            --   sem NF = valor previsto no pedido;
            --   com NF = o mesmo total fiscal de Lancado (NF), incluindo impostos.
            CAST(
                CASE
                    WHEN N."DocEntryNF" IS NOT NULL
                        THEN COALESCE(N."Lancado (NF)", 0)
                    ELSE COALESCE(B."Valor Variavel", 0)
                END
            AS DECIMAL(19,6)) AS "Valor Variavel",

            -- Imposto retido informado pela propria VW_FLUXO_NFSAIDAPARC.
            -- Coluna de validacao: nao realiza novo abatimento nesta consulta.
            CAST(
                CASE
                    WHEN N."DocEntryNF" IS NOT NULL
                        THEN COALESCE(N."ImpRet", 0)
                    ELSE 0
                END
            AS DECIMAL(19,6)) AS "ImpRet",

            -- Lançado NF: Origem ESTRITA na Nota Fiscal (Sem duplicação)
            CAST(
                CASE
                    WHEN N."DocEntryNF" IS NOT NULL
                        THEN COALESCE(N."Lancado (NF)", 0)
                    ELSE 0
                END
            AS DECIMAL(19,6)) AS "Lancado (NF)",

            -- A RECEBER: prioriza a NF; sem NF, permanece o previsto do pedido.
            CAST(
                CASE 
                    WHEN N."DocEntryNF" IS NOT NULL THEN COALESCE(N."Lancado (NF)", 0)
                    ELSE COALESCE(B."Valor Mes", 0)
                END
            AS DECIMAL(19,6)) AS "A RECEBER",

            -- Recebido
            CAST(COALESCE(RC."Recebido", 0) AS DECIMAL(19,6)) AS "Recebido",
            RC."TrsfrDate" AS "Data Receb.",
            N."Parcela",

            -- Variação
            CAST(
                CASE
                    WHEN COALESCE(RC."Recebido", 0) <> 0 THEN
                        COALESCE(RC."Recebido", 0) - COALESCE(N."Lancado (NF)", B."Valor Mes", 0)
                    ELSE 0
                END
            AS DECIMAL(19,6)) AS "Var Realiz",

            COALESCE(B."DocNumPed", N."BaseRefPed") AS "DocNumPed",
            COALESCE(B."LinhaPed", N."BaseLinePed") AS "LinhaPed",
            B."Usage",

            N."Centro Custo",
            N."Class.Financ.",
            N."DocNumSAP",

            RC."InvType",
            RC."ContaRecebimento",

            COALESCE(N."Comments", B."Comments") AS "Comments"

        FROM DadosBase B

        FULL OUTER JOIN DadosNotaConsolidada N
            ON B."DocEntryPed" = N."BaseRefPed"
           AND B."LinhaPed"    = N."BaseLinePed"

        LEFT JOIN DadosRec RC
            ON N."DocEntryNF" = RC."DocEntryNF"
           AND N."Parcela"    = RC."Parcela"

        -- Clientes PAC representam vendas recebidas por cartao.
        -- O valor permanece somente na agenda diaria da conta contabil do cartao.
        WHERE COALESCE(B."CardCode", N."CardCode", RC."CardCode", '') NOT LIKE 'PAC%'
          -- A parcela fechada permanece no relacionamento para impedir que o pedido
          -- volte como PREVISTO, mas nao compoe o fluxo a receber.
          AND
          (
              N."DocEntryNF" IS NULL
              OR
              (
                  COALESCE(N."Status Parcela SAP", 'O') <> 'C'
                  AND COALESCE(N."Recebido Parcela SAP", 0)
                      < COALESCE(N."Valor Parcela SAP", 0) - 0.000001
              )
          )
    ),

    -- 8. ACRESCENTA A AGENDA DE CARTOES AO FLUXO OPERACIONAL
    Detalhe AS
    (
        SELECT * FROM DetalheOperacional
        UNION ALL
        SELECT * FROM DadosCartao
    )

-- 6. TOTALIZADOR E SAÍDA
SELECT
    1 AS "_ord",
    CAST(NULL AS INTEGER)         AS "Ano",
    CAST(NULL AS INTEGER)         AS "MesNum",
    CAST(NULL AS DATE)            AS "Vencimento",
    CAST('TOTAL' AS NVARCHAR(50)) AS "Status Previsão",
    CAST(NULL AS NVARCHAR(30))    AS "Cod.Cliente",
    CAST('TOTAL GERAL' AS NVARCHAR(200)) AS "Nome Cliente",

    CAST(SUM("Valor Ano") AS DECIMAL(19,6))      AS "Valor Ano",
    CAST(SUM("Valor Mes") AS DECIMAL(19,6))      AS "Valor Mes",
    CAST(SUM("Valor Variavel") AS DECIMAL(19,6)) AS "Valor Variavel",
    CAST(SUM("ImpRet") AS DECIMAL(19,6))         AS "ImpRet",
    CAST(SUM("Lancado (NF)") AS DECIMAL(19,6))   AS "Lancado (NF)",
    CAST(SUM("A RECEBER") AS DECIMAL(19,6))      AS "A RECEBER",
    CAST(SUM("Recebido") AS DECIMAL(19,6))       AS "Recebido",

    CAST(NULL AS NVARCHAR(30)) AS "Data Receb.",
    CAST(NULL AS INTEGER)      AS "Parcela",

    CAST(SUM("Var Realiz") AS DECIMAL(19,6))     AS "Var Realiz",

    CAST(NULL AS NVARCHAR(30))  AS "CFO",
    CAST(NULL AS NVARCHAR(200)) AS "Nome CFO",
    CAST(NULL AS NVARCHAR(200)) AS "Tipo CFO",
    CAST(NULL AS NVARCHAR(200)) AS "Raiz CFO",
    CAST(NULL AS NVARCHAR(30))  AS "CCusto",
    CAST(NULL AS NVARCHAR(200)) AS "Nome CCusto",
    CAST(NULL AS NVARCHAR(30))  AS "Centro Custo",
    CAST(NULL AS NVARCHAR(30))  AS "Class.Financ.",
    CAST(NULL AS NVARCHAR(200)) AS "ContaRecebimento",
    CAST(NULL AS NVARCHAR(30))  AS "Comments"

FROM Detalhe

UNION ALL

SELECT 
    0 AS "_ord",
    "Ano",
    "MesNum",
    "Vencimento",
    "Status Previsão",
    "Cod.Cliente",
    "Nome Cliente",

    "Valor Ano",
    "Valor Mes",
    "Valor Variavel",
    "ImpRet",
    "Lancado (NF)",
    "A RECEBER",
    "Recebido",
    CAST("Data Receb." AS NVARCHAR(30)) AS "Data Receb.",
    "Parcela",
    "Var Realiz",
    "CFO",
    "Nome CFO",
    "Tipo CFO",
    "Raiz CFO",
    "CCusto",
    "Nome CCusto",
    "Centro Custo",
    "Class.Financ.",
    "ContaRecebimento",
    "Comments"

FROM Detalhe

ORDER BY 
    "_ord" DESC,
    "Ano",
    "Nome Cliente",
    "Vencimento",
    "Status Previsão";