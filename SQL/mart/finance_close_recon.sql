-- minimal as-Of Close Simulation
USE DataCenterRevenue;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'sim')
    EXEC('CREATE SCHEMA sim');
GO

IF OBJECT_ID('sim.params_close', 'U') IS NULL
BEGIN
    CREATE TABLE sim.params_close (
        id INT PRIMARY KEY,
        cutoff_day_of_month INT NOT NULL,   -- ex 3 = include postings through the 3rd of next month
        created_at DATETIME NOT NULL DEFAULT GETDATE()
    );
END
GO

-- set cutoff rule (change 3 to 1/2/5 as desired)
MERGE sim.params_close AS t
USING (SELECT 1 AS id, 3 AS cutoff_day_of_month) AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET cutoff_day_of_month = s.cutoff_day_of_month
WHEN NOT MATCHED THEN INSERT (id, cutoff_day_of_month) VALUES (s.id, s.cutoff_day_of_month);
GO

-- create recognized month view (as of close)
-- use posting_date to determine which month revenue is recognized in the close
-- if posting happens in the first n days of next month, it stays in the prior month
CREATE OR ALTER VIEW sim.v_erp_invoice_line_asof_close AS
WITH p AS (
    SELECT cutoff_day_of_month
    FROM sim.params_close
    WHERE id = 1
),
late_sim AS (
    SELECT
        f.*,
        CASE
            -- simulate approx 8% late ERP postings
            WHEN revenue_type = 'recurring'
             AND ABS(CHECKSUM(CONCAT(invoice_id, invoice_line_id))) % 100 < 8
            THEN DATEADD(DAY, 2, EOMONTH(invoice_month))
            ELSE posting_date
        END AS simulated_posting_date
    FROM raw.fact_invoice_line f
)
SELECT
    *,
    CASE
        WHEN simulated_posting_date > EOMONTH(invoice_month)
         AND DATEFROMPARTS(YEAR(simulated_posting_date), MONTH(simulated_posting_date), 1)
             = DATEADD(MONTH, 1, invoice_month)
         AND DAY(simulated_posting_date) <= (SELECT cutoff_day_of_month FROM p)
        THEN invoice_month
        ELSE DATEFROMPARTS(YEAR(simulated_posting_date), MONTH(simulated_posting_date), 1)
    END AS recognized_month
FROM late_sim;
GO


-- ERP monthly totals as of close
CREATE OR ALTER VIEW sim.v_erp_revenue_monthly_asof_close AS
SELECT
    recognized_month AS month,
    CAST(SUM(amount) AS DECIMAL(14,2)) AS erp_revenue_total
FROM sim.v_erp_invoice_line_asof_close
GROUP BY recognized_month;
GO

-- revenue true up logic (minimal + explainable)
-- Create true-up table (auditable)
IF OBJECT_ID('sim.fact_revenue_trueup_monthly', 'U') IS NULL
BEGIN
    CREATE TABLE sim.fact_revenue_trueup_monthly (
        month DATE PRIMARY KEY,
        trueup_amount DECIMAL(14,2) NOT NULL,
        trueup_reason VARCHAR(50) NOT NULL,
        created_at DATETIME NOT NULL DEFAULT GETDATE()
    );
END
GO

-- populate true-ups (deterministic + rerunnable)
-- Rule, 2% uplift in months where any contract is on version 2 (amendment driven adjustment).
-- rerunnable clear and rebuild
DELETE FROM sim.fact_revenue_trueup_monthly;
GO

INSERT INTO sim.fact_revenue_trueup_monthly (month, trueup_amount, trueup_reason)
SELECT
    m.month,
    CAST(0.02 * SUM(m.erp_revenue_total) AS DECIMAL(14,2)) AS trueup_amount,
    'Contract Amendment True-Up' AS trueup_reason
FROM mart.mart_contract_monthly m
WHERE EXISTS (
    SELECT 1
    FROM mart.mart_contract_monthly x
    WHERE x.month = m.month
      AND x.contract_version = 2
)
GROUP BY m.month;
GO

-- ERP totals including true up (as of close)
CREATE OR ALTER VIEW sim.v_erp_revenue_monthly_asof_close_with_trueup AS
SELECT
    e.month,
    CAST(e.erp_revenue_total + COALESCE(t.trueup_amount, 0) AS DECIMAL(14,2)) AS erp_revenue_total,
    COALESCE(t.trueup_amount, 0) AS trueup_amount,
    t.trueup_reason
FROM sim.v_erp_revenue_monthly_asof_close e
LEFT JOIN sim.fact_revenue_trueup_monthly t
    ON e.month = t.month;
GO

-- point recon ERP baseline to �as of close + true up�
--leave recon.v_mart_revenue_monthly_total as is
CREATE OR ALTER VIEW recon.v_erp_revenue_monthly_total AS
SELECT
    month,
    erp_revenue_total
FROM sim.v_erp_revenue_monthly_asof_close_with_trueup;
GO

-- validation 
-- see recognized month logic in action
SELECT TOP 20
    invoice_month,
    posting_date,
    recognized_month,
    amount,
    revenue_type
FROM sim.v_erp_invoice_line_asof_close
ORDER BY posting_date DESC;

-- ERP totals with true up
SELECT TOP 24 *
FROM sim.v_erp_revenue_monthly_asof_close_with_trueup
ORDER BY month DESC;

-- recon results (after refresh)
SELECT TOP 24 *
FROM recon.recon_erp_vs_mart_monthly
ORDER BY month DESC;

-- confirm the simulation is actually affecting numbers:
-- does recognized_month differ anywhere?
SELECT TOP 25
  invoice_month, posting_date, recognized_month, amount, revenue_type
FROM sim.v_erp_invoice_line_asof_close
WHERE recognized_month <> invoice_month
ORDER BY posting_date DESC;

-- should now see: Some red/yellow months
-- variance buckets = timing / Close Cutoff
-- explainable drift

-- Recognized month should now differ
SELECT TOP 20
  invoice_month, simulated_posting_date, recognized_month, amount
FROM sim.v_erp_invoice_line_asof_close
WHERE recognized_month <> invoice_month
ORDER BY simulated_posting_date DESC;

-- ERP totals shift
SELECT TOP 24 *
FROM sim.v_erp_revenue_monthly_asof_close_with_trueup
ORDER BY month DESC;

-- Recon lights up
SELECT TOP 24 *
FROM recon.recon_erp_vs_mart_monthly
WHERE variance_amount <> 0
ORDER BY month DESC;
