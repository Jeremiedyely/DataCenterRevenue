-- Control & Data integrity (the view + the exception tables� that Power BI reads)

-- main controls view (Power BI page source).  
-- single, clean table for the �Controls & Data integrity� page.
CREATE OR ALTER VIEW recon.v_controls_data_integrity AS
SELECT
    month,
    erp_revenue_total,
    mart_revenue_total,
    variance_amount,
    variance_pct,
    variance_bucket,
    control_status,
    last_reconciled_at
FROM recon.recon_erp_vs_mart_monthly;
GO

-- Create contract level variance exception. (where to drill in)
-- When a month is yellow/red, this shows which contracts drove it.
CREATE OR ALTER VIEW recon.v_contract_variance_monthly AS
SELECT
    mc.month,
    mc.contract_id,
    mc.contract_version,

    mc.erp_revenue_total AS contract_erp_revenue,
    mc.allocated_power_cost,
    mc.gross_margin,

    mc.late_reading_days,
    mc.estimated_days,
    mc.true_up_flag,

    -- usage signals
    mc.total_kw,
    mc.avg_daily_kw,
    mc.peak_kw,

    -- simple flags for exception reporting
    CASE WHEN mc.late_reading_days > 0 THEN 1 ELSE 0 END AS late_flag,
    CASE WHEN mc.estimated_days > 0 THEN 1 ELSE 0 END AS estimated_flag,
    CASE WHEN mc.true_up_flag = 1 THEN 1 ELSE 0 END AS true_up_flag2
FROM mart.mart_contract_monthly mc;
GO

-- create �variance reason� classification at contract month level
-- same idea as variance_bucket but at the contract-month detail so you can show counts by reason.
CREATE OR ALTER VIEW recon.v_contract_exception_reason AS
SELECT
    month,
    contract_id,
    contract_version,
    CASE
        WHEN late_reading_days > 0 THEN 'Late Meter Data'
        WHEN estimated_days > 0 THEN 'Estimated Usage'
        WHEN true_up_flag = 1 THEN 'Power Cost True-Up'
        ELSE 'No Flag'
    END AS exception_reason
FROM mart.mart_contract_monthly;
GO

-- create an �exceptions only� view (for dashboards)
-- Power BI can show only the contracts that need attention.
CREATE OR ALTER VIEW recon.v_contract_exceptions_only AS
SELECT
    mc.*
FROM mart.mart_contract_monthly mc
WHERE mc.late_reading_days > 0
   OR mc.estimated_days > 0
   OR mc.true_up_flag = 1;
GO

-- create a �Controls Summary� view (executive-friendly)
-- One row per month with counts of exceptions + risk intensity.
CREATE OR ALTER VIEW recon.v_controls_summary AS
SELECT
    mc.month,
    COUNT(*) AS contract_rows,
    SUM(CASE WHEN mc.late_reading_days > 0 THEN 1 ELSE 0 END) AS contracts_with_late_data,
    SUM(CASE WHEN mc.estimated_days > 0 THEN 1 ELSE 0 END) AS contracts_with_estimated_data,
    SUM(CASE WHEN mc.true_up_flag = 1 THEN 1 ELSE 0 END) AS contracts_with_trueups,
    SUM(CASE WHEN mc.gross_margin < 0 THEN 1 ELSE 0 END) AS contracts_negative_margin
FROM mart.mart_contract_monthly mc
GROUP BY mc.month;
GO

-- verification check
SELECT TOP 12 * FROM recon.v_controls_data_integrity ORDER BY month DESC;
SELECT TOP 12 * FROM recon.v_controls_summary ORDER BY month DESC;
SELECT TOP 20 * FROM recon.v_contract_exceptions_only ORDER BY month DESC, contract_id;
