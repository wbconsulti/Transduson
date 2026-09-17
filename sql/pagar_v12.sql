/* SELECT FROM OJDT X10 */

Declare pDataIni Date;
Declare pDataFim Date;
Declare pDataCorte Date;

pDataIni   := /* X10."RefDate" as "Data Inicio" */ '[%0]';
pDataFim   := /* X10."RefDate" as "Data Final"  */ '[%1]';
pDataCorte := /* X10."RefDate" as "Data Corte"  */ '[%2]';


WITH

/* ================================================================
   1. PREVISÃO ORIGINAL - PEDIDOS
   ================================================================ */
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

        SUM(COALESCE("Valor Ano", 0))      AS "Valor Ano",
        SUM(COALESCE("Valor Mes", 0))      AS "Valor Mes",
        SUM(COALESCE("Valor Variavel", 0)) AS "Valor Variavel"

    FROM "VW_FLUXO_PREVPEDIDO"

    WHERE "Vencimento" BETWEEN :pDataIni AND :pDataFim

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


/* ================================================================
   2. CHAVES DOS PEDIDOS EXISTENTES NO FLUXO DO PERÍODO
   ================================================================ */
ChavesBase AS
(
    SELECT DISTINCT
        "DocEntryPed",
        "LinhaPed"
    FROM DadosBase
),


/* ================================================================
   3. TODOS OS PAGAMENTOS DO PERÍODO
   ================================================================ */
DadosPagTodos AS
(
    SELECT 
        "DocEntryNF",
        "Parcela",
        "CardCode",
        "NomeCredor",
        "CFO",
        "InvType",
        "ContaPagamento",

        MAX("TrsfrDate") AS "TrsfrDate",
        SUM(COALESCE("Pago", 0)) AS "Pago"

    FROM "VW_FLUXO_PAGAMENTOS"

    WHERE "TrsfrDate" BETWEEN :pDataIni AND :pDataFim

    GROUP BY
        "DocEntryNF",
        "Parcela",
        "CardCode",
        "NomeCredor",
        "CFO",
        "InvType",
        "ContaPagamento"
),


/* ================================================================
   4. PAGAMENTOS DE NF DE ENTRADA - OBJETO 18
   Consolidamos por NF + parcela para evitar multiplicação por conta
   ================================================================ */
DadosPagNF AS
(
    SELECT
        "DocEntryNF",
        "Parcela",

        MAX("CardCode")        AS "CardCode",
        MAX("NomeCredor")      AS "NomeCredor",
        MAX("CFO")             AS "CFO",
        MAX("ContaPagamento")  AS "ContaPagamento",
        MAX("TrsfrDate")       AS "TrsfrDate",

        CAST(18 AS INTEGER) AS "InvType",

        SUM(COALESCE("Pago",0)) AS "Pago"

    FROM DadosPagTodos

    WHERE "InvType" = 18

    GROUP BY
        "DocEntryNF",
        "Parcela"
),


/* ================================================================
   5. PAGAMENTOS DE FATURA DE ADIANTAMENTO - OBJETO 204
   Aqui DocEntryNF representa, na prática, o DocEntry da ODPO
   ================================================================ */
DadosPagAdiant AS
(
    SELECT
        "DocEntryNF" AS "DocEntryAdiant",

        MAX("CardCode")       AS "CardCode",
        MAX("NomeCredor")     AS "NomeCredor",
        MAX("CFO")            AS "CFO",
        MAX("ContaPagamento") AS "ContaPagamento",
        MAX("TrsfrDate")      AS "TrsfrDate",

        CAST(204 AS INTEGER) AS "InvType",

        SUM(COALESCE("Pago",0)) AS "Pago"

    FROM DadosPagTodos

    WHERE "InvType" = 204

    GROUP BY
        "DocEntryNF"
),


/* ================================================================
   6. OUTROS PAGAMENTOS
   Continuam sendo tratados como fora do fluxo documental atual
   ================================================================ */
DadosPagOutros AS
(
    SELECT *
    FROM DadosPagTodos

    WHERE COALESCE("InvType", -1) NOT IN (18, 204)
),


/* ================================================================
   7. VÍNCULO NF DE ENTRADA -> PEDIDO
   Mantida a lógica já existente por enquanto
   ================================================================ */
VinculoNotaPedido AS
(
    SELECT 
        "DocEntry",

        MAX("BaseEntry") AS "BaseRefPed",
        MAX("BaseLine")  AS "BaseLinePed"

    FROM PCH1

    WHERE "BaseEntry" IS NOT NULL

    GROUP BY
        "DocEntry"
),


/* ================================================================
   8. NOTAS FISCAIS PARCELADAS
   Além das NFs com vencimento no período, traz NF paga no período.
   ================================================================ */
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

        COALESCE(V."BaseRefPed", NF."BaseRefPed")
            AS "BaseRefPed",

        COALESCE(V."BaseLinePed", NF."BaseLinePed")
            AS "BaseLinePed",

        MAX(COALESCE(NF."Valor Ano", 0))
            AS "Valor Ano NF",

        MAX(COALESCE(NF."Valor Mes", 0))
            AS "Valor Mes NF",

        MAX(COALESCE(NF."Valor Variavel", 0))
            AS "Valor Variavel NF",

        MAX(COALESCE(NF."ImpRet", 0))
            AS "ImpRet",

        MAX(COALESCE(NF."Lancado (NF)", 0))
            AS "Lancado (NF)"

    FROM "VW_FLUXO_NFENTRPARC" NF

    LEFT JOIN VinculoNotaPedido V
        ON V."DocEntry" = NF."DocEntryNF"

    WHERE
        NF."CreateDateNF" <= :pDataCorte

        AND
        (
            NF."Vencimento" BETWEEN :pDataIni AND :pDataFim

            OR EXISTS
            (
                SELECT 1
                FROM DadosPagNF PGX

                WHERE PGX."DocEntryNF" = NF."DocEntryNF"
                  AND PGX."Parcela"    = NF."Parcela"
            )
        )

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


/* ================================================================
   9. FATURA DE ADIANTAMENTO -> PEDIDO DE COMPRA

   ODPO = Cabeçalho Fatura de Adiantamento fornecedor
   DPO1 = Linhas

   BaseType 22 = Pedido de Compra
   ================================================================ */
AdiantamentoLinha AS
(
    SELECT
        D0."DocEntry" AS "DocEntryAdiant",

        D1."BaseEntry" AS "DocEntryPed",
        D1."BaseLine"  AS "LinhaPed",

        SUM(
            COALESCE(D1."LineTotal", 0)
        ) AS "ValorLinhaAdiant"

    FROM ODPO D0

    INNER JOIN DPO1 D1
        ON D1."DocEntry" = D0."DocEntry"

    WHERE
        D0."CANCELED" = 'N'

        AND D1."BaseType" = 22

        AND D1."BaseEntry" IS NOT NULL

        AND D1."BaseEntry" >= 0

    GROUP BY
        D0."DocEntry",
        D1."BaseEntry",
        D1."BaseLine"
),


/* ================================================================
   10. SOMENTE ADIANTAMENTOS CUJO PEDIDO ESTÁ NO FLUXO DO PERÍODO
   ================================================================ */
AdiantamentoLinhaFluxo AS
(
    SELECT
        A.*

    FROM AdiantamentoLinha A

    INNER JOIN ChavesBase B
        ON B."DocEntryPed" = A."DocEntryPed"
       AND B."LinhaPed"    = A."LinhaPed"
),


/* ================================================================
   11. BASE PARA RATEAR PAGAMENTO DO ADIANTAMENTO ENTRE AS LINHAS
   Normalmente haverá uma linha; rateio protege cenários multilinha.
   ================================================================ */
AdiantamentoTotalFluxo AS
(
    SELECT
        "DocEntryAdiant",

        SUM(
            COALESCE("ValorLinhaAdiant",0)
        ) AS "BaseRateio",

        COUNT(*) AS "QtdVinculos"

    FROM AdiantamentoLinhaFluxo

    GROUP BY
        "DocEntryAdiant"
),


/* ================================================================
   12. PAGAMENTO DO ADIANTAMENTO ASSOCIADO AO PEDIDO/LINHA

   Caso TXG:
   PC -> ODPO -> Pagamento
   sem necessidade de NF existir.
   ================================================================ */
AdiantamentoPagoPedidoLinha AS
(
    SELECT
        A."DocEntryPed",
        A."LinhaPed",

        MAX(PG."TrsfrDate")
            AS "TrsfrDate",

        MAX(PG."ContaPagamento")
            AS "ContaPagamento",

        SUM
        (
            PG."Pago"
            *
            CASE

                WHEN ABS(
                    COALESCE(T."BaseRateio",0)
                ) > 0.000001

                THEN
                    A."ValorLinhaAdiant"
                    /
                    T."BaseRateio"

                ELSE
                    CAST(1 AS DECIMAL(19,6))
                    /
                    NULLIF(T."QtdVinculos",0)

            END

        ) AS "Pago"

    FROM AdiantamentoLinhaFluxo A

    INNER JOIN AdiantamentoTotalFluxo T
        ON T."DocEntryAdiant" = A."DocEntryAdiant"

    INNER JOIN DadosPagAdiant PG
        ON PG."DocEntryAdiant" = A."DocEntryAdiant"

    GROUP BY
        A."DocEntryPed",
        A."LinhaPed"
),


/* ================================================================
   13. DETALHE PRINCIPAL
   Pedido -> NF -> Pagamento
   ou
   Pedido -> Adiantamento -> Pagamento
   ================================================================ */
DetalhePrincipal AS
(
    SELECT

        COALESCE(
            B."Ano",
            N."Ano",
            YEAR(PG."TrsfrDate")
        ) AS "Ano",

        COALESCE(
            B."MesNum",
            N."MesNum",
            MONTH(PG."TrsfrDate")
        ) AS "MesNum",

        COALESCE(
            B."Vencimento",
            N."Vencimento",
            PG."TrsfrDate"
        ) AS "Vencimento",


        /* Se encontrou pedido, mantém o status do fluxo.
           Adiantamento pago NÃO vira FORA DO FLUXO. */
        COALESCE(
            B."Status Previsão",
            N."Status Previsão",
            'FORA DO FLUXO'
        ) AS "Status Previsão",


        COALESCE(
            B."CardCode",
            N."CardCode",
            PG."CardCode"
        ) AS "Cod.Fornec",

        COALESCE(
            B."CardName",
            N."CardName",
            PG."NomeCredor"
        ) AS "Nome Fornec",


        COALESCE(
            B."CFO",
            N."CFO",
            PG."CFO"
        ) AS "CFO",

        COALESCE(
            B."Nome CFO",
            N."Nome CFO"
        ) AS "Nome CFO",

        COALESCE(
            B."Tipo CFO",
            N."Tipo CFO"
        ) AS "Tipo CFO",

        COALESCE(
            B."Raiz CFO",
            N."Raiz CFO"
        ) AS "Raiz CFO",


        COALESCE(
            B."CCusto",
            N."CCusto"
        ) AS "CCusto",

        COALESCE(
            B."Nome CCusto",
            N."Nome CCusto"
        ) AS "Nome CCusto",


        /* VALOR ANO */
        CAST(
            COALESCE(
                B."Valor Ano",
                N."Valor Ano NF",
                0
            )
        AS DECIMAL(19,6))
        AS "Valor Ano",


        /* VALOR MÊS */
        CAST(
            CASE

                WHEN N."DocEntryNF" IS NOT NULL
                    THEN COALESCE(N."Valor Mes NF",0)

                ELSE
                    COALESCE(B."Valor Mes",0)

            END
        AS DECIMAL(19,6))
        AS "Valor Mes",


        /* VALOR VARIÁVEL */
        CAST(
            CASE

                WHEN N."DocEntryNF" IS NOT NULL
                    THEN COALESCE(N."Lancado (NF)",0)

                ELSE
                    COALESCE(B."Valor Variavel",0)

            END
        AS DECIMAL(19,6))
        AS "Valor Variavel",


        /* IMPOSTOS */
        CAST(
            CASE

                WHEN N."DocEntryNF" IS NOT NULL
                    THEN COALESCE(N."ImpRet",0)

                ELSE 0

            END
        AS DECIMAL(19,6))
        AS "ImpRet",


        /* LANÇADO NF */
        CAST(
            CASE

                WHEN N."DocEntryNF" IS NOT NULL
                    THEN COALESCE(N."Lancado (NF)",0)

                ELSE 0

            END
        AS DECIMAL(19,6))
        AS "Lancado (NF)",


        /* A PAGAR */
        CAST(
            CASE

                WHEN N."DocEntryNF" IS NOT NULL
                    THEN COALESCE(N."Lancado (NF)",0)

                ELSE
                    COALESCE(B."Valor Mes",0)

            END
        AS DECIMAL(19,6))
        AS "A PAGAR",


        /* ========================================================
           PAGO

           1. Havendo NF, utiliza pagamento da NF.
           2. Sem NF, mas havendo adiantamento pago vinculado
              ao Pedido, utiliza pagamento da ODPO.
           3. Pagamento de NF sem documento encontrado continua
              aparecendo como FORA DO FLUXO.
           ======================================================== */
        CAST(
            CASE

                WHEN N."DocEntryNF" IS NOT NULL
                    THEN COALESCE(PG."Pago",0)

                WHEN B."DocEntryPed" IS NOT NULL
                 AND AP."DocEntryPed" IS NOT NULL
                    THEN COALESCE(AP."Pago",0)

                ELSE
                    COALESCE(PG."Pago",0)

            END
        AS DECIMAL(19,6))
        AS "Pago",


        CASE

            WHEN N."DocEntryNF" IS NOT NULL
                THEN PG."TrsfrDate"

            WHEN B."DocEntryPed" IS NOT NULL
             AND AP."DocEntryPed" IS NOT NULL
                THEN AP."TrsfrDate"

            ELSE
                PG."TrsfrDate"

        END AS "Data Pagto",


        N."Parcela",


        /* VARIAÇÃO REALIZADO */
        CAST(
            CASE

                WHEN N."DocEntryNF" IS NOT NULL
                 AND COALESCE(PG."Pago",0) <> 0

                    THEN
                        COALESCE(PG."Pago",0)
                        -
                        COALESCE(N."Lancado (NF)",0)


                WHEN N."DocEntryNF" IS NULL
                 AND AP."DocEntryPed" IS NOT NULL
                 AND COALESCE(AP."Pago",0) <> 0

                    THEN
                        COALESCE(AP."Pago",0)
                        -
                        COALESCE(B."Valor Mes",0)


                WHEN COALESCE(PG."Pago",0) <> 0

                    THEN
                        COALESCE(PG."Pago",0)


                ELSE 0

            END
        AS DECIMAL(19,6))
        AS "Var Realiz",


        N."Centro Custo",

        N."Class.Financ.",


        CASE

            WHEN N."DocEntryNF" IS NOT NULL
                THEN PG."ContaPagamento"

            WHEN AP."DocEntryPed" IS NOT NULL
                THEN AP."ContaPagamento"

            ELSE
                PG."ContaPagamento"

        END AS "ContaPagamento",


        COALESCE(
            N."Comments",
            B."Comments"
        ) AS "Comments"


    FROM DadosBase B


    FULL OUTER JOIN DadosNotaConsolidada N

        ON B."DocEntryPed" = N."BaseRefPed"

       AND B."LinhaPed"    = N."BaseLinePed"


    FULL OUTER JOIN DadosPagNF PG

        ON N."DocEntryNF" = PG."DocEntryNF"

       AND N."Parcela"    = PG."Parcela"


    LEFT JOIN AdiantamentoPagoPedidoLinha AP

        ON B."DocEntryPed" = AP."DocEntryPed"

       AND B."LinhaPed"    = AP."LinhaPed"
),


/* ================================================================
   14. ADIANTAMENTOS PAGOS SEM PEDIDO PRESENTE NO FLUXO DO PERÍODO

   Estes continuam classificados como FORA DO FLUXO porque,
   embora exista ODPO, o pedido/previsão correspondente não está
   presente em DadosBase para o período analisado.
   ================================================================ */
DetalheAdiantOrfao AS
(
    SELECT

        YEAR(PG."TrsfrDate") AS "Ano",

        MONTH(PG."TrsfrDate") AS "MesNum",

        PG."TrsfrDate" AS "Vencimento",

        CAST(
            'FORA DO FLUXO'
            AS NVARCHAR(50)
        ) AS "Status Previsão",

        PG."CardCode" AS "Cod.Fornec",

        PG."NomeCredor" AS "Nome Fornec",

        PG."CFO" AS "CFO",

        CAST(NULL AS NVARCHAR(200))
            AS "Nome CFO",

        CAST(NULL AS NVARCHAR(200))
            AS "Tipo CFO",

        CAST(NULL AS NVARCHAR(200))
            AS "Raiz CFO",

        CAST(NULL AS NVARCHAR(30))
            AS "CCusto",

        CAST(NULL AS NVARCHAR(200))
            AS "Nome CCusto",

        CAST(0 AS DECIMAL(19,6))
            AS "Valor Ano",

        CAST(0 AS DECIMAL(19,6))
            AS "Valor Mes",

        CAST(0 AS DECIMAL(19,6))
            AS "Valor Variavel",

        CAST(0 AS DECIMAL(19,6))
            AS "ImpRet",

        CAST(0 AS DECIMAL(19,6))
            AS "Lancado (NF)",

        CAST(0 AS DECIMAL(19,6))
            AS "A PAGAR",

        CAST(
            COALESCE(PG."Pago",0)
            AS DECIMAL(19,6)
        ) AS "Pago",

        PG."TrsfrDate"
            AS "Data Pagto",

        CAST(NULL AS INTEGER)
            AS "Parcela",

        CAST(
            COALESCE(PG."Pago",0)
            AS DECIMAL(19,6)
        ) AS "Var Realiz",

        CAST(NULL AS NVARCHAR(30))
            AS "Centro Custo",

        CAST(NULL AS NVARCHAR(30))
            AS "Class.Financ.",

        PG."ContaPagamento"
            AS "ContaPagamento",

        CAST(NULL AS NVARCHAR(254))
            AS "Comments"


    FROM DadosPagAdiant PG

    WHERE NOT EXISTS
    (
        SELECT 1

        FROM AdiantamentoLinhaFluxo A

        WHERE A."DocEntryAdiant"
            = PG."DocEntryAdiant"
    )
),


/* ================================================================
   15. OUTROS TIPOS DE PAGAMENTO
   ================================================================ */
DetalheOutros AS
(
    SELECT

        YEAR(PG."TrsfrDate") AS "Ano",

        MONTH(PG."TrsfrDate") AS "MesNum",

        PG."TrsfrDate" AS "Vencimento",

        CAST(
            'FORA DO FLUXO'
            AS NVARCHAR(50)
        ) AS "Status Previsão",

        PG."CardCode"
            AS "Cod.Fornec",

        PG."NomeCredor"
            AS "Nome Fornec",

        PG."CFO"
            AS "CFO",

        CAST(NULL AS NVARCHAR(200))
            AS "Nome CFO",

        CAST(NULL AS NVARCHAR(200))
            AS "Tipo CFO",

        CAST(NULL AS NVARCHAR(200))
            AS "Raiz CFO",

        CAST(NULL AS NVARCHAR(30))
            AS "CCusto",

        CAST(NULL AS NVARCHAR(200))
            AS "Nome CCusto",

        CAST(0 AS DECIMAL(19,6))
            AS "Valor Ano",

        CAST(0 AS DECIMAL(19,6))
            AS "Valor Mes",

        CAST(0 AS DECIMAL(19,6))
            AS "Valor Variavel",

        CAST(0 AS DECIMAL(19,6))
            AS "ImpRet",

        CAST(0 AS DECIMAL(19,6))
            AS "Lancado (NF)",

        CAST(0 AS DECIMAL(19,6))
            AS "A PAGAR",

        CAST(
            COALESCE(PG."Pago",0)
            AS DECIMAL(19,6)
        ) AS "Pago",

        PG."TrsfrDate"
            AS "Data Pagto",

        PG."Parcela",

        CAST(
            COALESCE(PG."Pago",0)
            AS DECIMAL(19,6)
        ) AS "Var Realiz",

        CAST(NULL AS NVARCHAR(30))
            AS "Centro Custo",

        CAST(NULL AS NVARCHAR(30))
            AS "Class.Financ.",

        PG."ContaPagamento"
            AS "ContaPagamento",

        CAST(NULL AS NVARCHAR(254))
            AS "Comments"

    FROM DadosPagOutros PG
),


/* ================================================================
   16. CONSOLIDAÇÃO FINAL
   ================================================================ */
Detalhe AS
(
    SELECT * FROM DetalhePrincipal

    UNION ALL

    SELECT * FROM DetalheAdiantOrfao

    UNION ALL

    SELECT * FROM DetalheOutros
)


/* ================================================================
   17. TOTALIZADOR
   ================================================================ */
SELECT

    1 AS "_ord",

    CAST(NULL AS INTEGER)
        AS "Ano",

    CAST(NULL AS INTEGER)
        AS "MesNum",

    CAST(NULL AS DATE)
        AS "Vencimento",

    CAST(
        'TOTAL'
        AS NVARCHAR(50)
    ) AS "Status Previsão",

    CAST(NULL AS NVARCHAR(30))
        AS "Cod.Fornec",

    CAST(
        'TOTAL GERAL'
        AS NVARCHAR(200)
    ) AS "Nome Fornec",


    CAST(
        SUM("Valor Ano")
        AS DECIMAL(19,6)
    ) AS "Valor Ano",

    CAST(
        SUM("Valor Mes")
        AS DECIMAL(19,6)
    ) AS "Valor Mes",

    CAST(
        SUM("Valor Variavel")
        AS DECIMAL(19,6)
    ) AS "Valor Variavel",

    CAST(
        SUM("ImpRet")
        AS DECIMAL(19,6)
    ) AS "ImpRet",

    CAST(
        SUM("Lancado (NF)")
        AS DECIMAL(19,6)
    ) AS "Lancado (NF)",

    CAST(
        SUM("A PAGAR")
        AS DECIMAL(19,6)
    ) AS "A PAGAR",

    CAST(
        SUM("Pago")
        AS DECIMAL(19,6)
    ) AS "Pago",

    CAST(NULL AS NVARCHAR(30))
        AS "Data Pagto",

    CAST(NULL AS INTEGER)
        AS "Parcela",

    CAST(
        SUM("Var Realiz")
        AS DECIMAL(19,6)
    ) AS "Var Realiz",

    CAST(NULL AS NVARCHAR(30))
        AS "CFO",

    CAST(NULL AS NVARCHAR(200))
        AS "Nome CFO",

    CAST(NULL AS NVARCHAR(200))
        AS "Tipo CFO",

    CAST(NULL AS NVARCHAR(200))
        AS "Raiz CFO",

    CAST(NULL AS NVARCHAR(30))
        AS "CCusto",

    CAST(NULL AS NVARCHAR(200))
        AS "Nome CCusto",

    CAST(NULL AS NVARCHAR(30))
        AS "Centro Custo",

    CAST(NULL AS NVARCHAR(30))
        AS "Class.Financ.",

    CAST(NULL AS NVARCHAR(30))
        AS "ContaPagamento",

    CAST(NULL AS NVARCHAR(254))
        AS "Comments"

FROM Detalhe


UNION ALL


/* ================================================================
   18. DETALHAMENTO
   ================================================================ */
SELECT

    0 AS "_ord",

    "Ano",
    "MesNum",
    "Vencimento",
    "Status Previsão",
    "Cod.Fornec",
    "Nome Fornec",

    "Valor Ano",
    "Valor Mes",
    "Valor Variavel",
    "ImpRet",
    "Lancado (NF)",
    "A PAGAR",
    "Pago",

    CAST(
        "Data Pagto"
        AS NVARCHAR(30)
    ) AS "Data Pagto",

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
    "ContaPagamento",
    "Comments"

FROM Detalhe


ORDER BY
    "_ord" DESC,
    "Ano",
    "Nome Fornec",
    "Vencimento",
    "Status Previsão";