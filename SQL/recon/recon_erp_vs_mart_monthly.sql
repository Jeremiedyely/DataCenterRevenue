-- Build ERP revenue totals (control baseline)
-- Raw ERP totals(no modeling, no allocation). This is the control anchor. 
CREATE VIEW recon.v_erp_revenue_monthly_total AS
SELECT
    invoice_month AS [month],
    SUM(amount) AS erp_revenue_total
FROM raw.fact_invoice_line
GROUP BY invoice_month;
GO

-- Build MART revenue totals
-- what executives see on dashboards. Must reconcile to ERP or explain why not 
CREATE VIEW recon.v_mart_revenue_monthly_total AS
SELECT
    month,
    SUM(erp_revenue_total) AS mart_revenue_total
FROM mart.mart_contract_monthly
GROUP BY month;
GO

-- control layer
-- reconciles ERP revenue to modeled revenue, flags material variance, explains root cause
-- and timestamps when finance last validated the numbers
CREATE TABLE recon.recon_erp_vs_mart_monthly (
    [month] DATE NOT NULL,
    erp_revenue_total DECIMAL(14,2) NULL,
    mart_revenue_total DECIMAL(14,2) NULL,
    variance_amount DECIMAL(14,2) NULL,
    variance_pct DECIMAL(6,2) NULL,
    variance_bucket VARCHAR(50) NULL,
    control_status VARCHAR(20) NULL,
    last_reconciled_at DATETIME NOT NULL,
    CONSTRAINT pk_recon_erp_vs_mart_monthly PRIMARY KEY ([month])
);
GO

-- independently calcuate monthly totals from ERP and from the modeled MART Only after both exist do I compare them.
IF OBJECT_ID('tempdb..#erp_monthly', 'U') IS NOT NULL DROP TABLE #erp_monthly;

SELECT
    invoice_month AS month,
    CAST(SUM(amount) AS DECIMAL(14,2)) AS erp_revenue_total
INTO #erp_monthly
FROM raw.fact_invoice_line
GROUP BY invoice_month;

-- Mart monthly totals (insight) Clear any previous run
IF OBJECT_ID('tempdb..#mart_monthly', 'U') IS NOT NULL DROP TABLE #mart_monthly;

SELECT
    month,
    CAST(SUM(erp_revenue_total) AS DECIMAL(14,2)) AS mart_revenue_total
INTO #mart_monthly
FROM mart.mart_contract_monthly
GROUP BY month;

-- Delete months we are about to refresh (idempotent)
DELETE r
FROM recon.recon_erp_vs_mart_monthly r
WHERE r.month IN (SELECT month FROM #erp_monthly)
   OR r.month IN (SELECT month FROM #mart_monthly);

-- insert refreshed recon rows (full outer join to catch missing months)
INSERT INTO recon.recon_erp_vs_mart_monthly (
    month,
    erp_revenue_total,
    mart_revenue_total,
    variance_amount,
    variance_pct,
    variance_bucket,
    control_status,
    last_reconciled_at
)
SELECT
    COALESCE(e.month, m.month) AS month,
    e.erp_revenue_total,
    m.mart_revenue_total,
    CAST(COALESCE(m.mart_revenue_total, 0) - COALESCE(e.erp_revenue_total, 0) AS DECIMAL(14,2)) AS variance_amount,
    CAST(
        CASE
            WHEN COALESCE(e.erp_revenue_total, 0) = 0 THEN 0
            ELSE ((COALESCE(m.mart_revenue_total, 0) - COALESCE(e.erp_revenue_total, 0))
                  / NULLIF(e.erp_revenue_total, 0)) * 100
        END
        AS DECIMAL(6,2)
    ) AS variance_pct,
    NULL AS variance_bucket,
    NULL AS control_status,
    GETDATE() AS last_reconciled_at
FROM #erp_monthly e
FULL OUTER JOIN #mart_monthly m
    ON e.month = m.month;

-- control thresholds 
UPDATE r
SET control_status =
    CASE
        WHEN ABS(COALESCE(r.variance_pct, 0)) < 1 THEN 'GREEN'
        WHEN ABS(COALESCE(r.variance_pct, 0)) BETWEEN 1 AND 3 THEN 'YELLOW'
        ELSE 'RED'
    END
FROM recon.recon_erp_vs_mart_monthly r;

-- root-cause bucketing (simple, explainable)
UPDATE r
SET variance_bucket =
    CASE
        WHEN ABS(COALESCE(r.variance_pct, 0)) < 1 THEN 'No Issue'
        WHEN EXISTS (
            SELECT 1
            FROM mart.mart_contract_monthly mc
            WHERE mc.month = r.month
              AND mc.late_reading_days > 0
        ) THEN 'Late Meter Data'
        WHEN EXISTS (
            SELECT 1
            FROM mart.mart_contract_monthly mc
            WHERE mc.month = r.month
              AND mc.estimated_days > 0
        ) THEN 'Estimated Usage'
        WHEN EXISTS (
            SELECT 1
            FROM mart.mart_contract_monthly mc
            WHERE mc.month = r.month
              AND mc.true_up_flag = 1
        ) THEN 'Power Cost True-Up'
        ELSE 'Timing / Mapping Difference'
    END
FROM recon.recon_erp_vs_mart_monthly r;

-- Output results (quick view) --
SELECT *
FROM recon.recon_erp_vs_mart_monthly
ORDER BY month;
GO

