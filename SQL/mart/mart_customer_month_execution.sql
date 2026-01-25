-- No mixing contract versions/amendments, no daily volatility, clean period close.
-- Preventing numbers changing later. 
CREATE TABLE mart.mart_contract_monthly (
    contract_id INT,
    contract_version INT,
    month DATE, 

    -- Contract structure (revenue boundaries)
    -- what client is allowed to use. Usage compared agaisnt and why overages or expansion exist.
    racks_entitled INT,
    power_commit_kw DECIMAL(10,2),

    -- Usage. Physics enter finance. 
    -- Change daily, drives energy cost, can exceed commitments. 
    total_kw DECIMAL(12,2),
    avg_daily_kw DECIMAL(12,2),
    peak_kw DECIMAL(12,2),

    -- Rack usage (capcity) 
    -- explain how usage is happening, support capacity planning, justify expansions or pricing changes.
    -- define capacity and context.revenue and cost are driven by how capacity is used under the contract.
    avg_racks_used DECIMAL(10,2),
    max_racks_used INT,

    -- Revenue (ERP enforcement)
    -- enforces billing and applies timing. Store ERP truth not assume it's correct. 
    erp_revenue_total DECIMAL(14,2),
    erp_mrr DECIMAL(14,2),
    erp_overage DECIMAL(14,2),
    erp_credits DECIMAL(14,2),

    -- Costs (margin physics) if number is wrong margin lie, pricing fails, can erase margin. operationally sensitive number.
    -- Client's share of total site power cost, allocated by usage. What was consumed, not estimated or sold. 
    --  Margin = Revenue - Cost. Must follow usage, not contracts
    allocated_power_cost DECIMAL(14,2), -- expose bad contracts, surface margin killers, force pricing discipline. 

    -- Margin (real output) after all structure and physics are respected. 
    -- Drives pricing strategy, client segmentation, expansion decisions, investor confidence
    -- gross_margin = revenue − allocated energy cost
    gross_margin DECIMAL(14,2),

    -- Risk / controls. 
    -- Report not just numbers but reliability when to trust them and when to expect movement. 
    late_reading_days INT, -- incomplete physcis ( physics didn't fully show up yet, cost alloc or usage-based margin is provisional)
    estimated_days INT, -- uncertainty (estimate can bias cost allocation, create futre reversals)
    true_up_flag BIT -- adjustments applied ( margin moved after the period, variance must be explainable)
);
GO
INSERT INTO mart.mart_contract_monthly
SELECT
    -- Mart grain
    c.contract_id,
    c.contract_version,
    u.usage_month AS [month],

    -- contract structure (what was sold). Where revenue is born.
    c.racks_entitled,
    c.power_commit_kw,

    -- usage metrcis (physics behavior) behavior that can drift inside contract structure.
    -- what actually happened operationally
    u.total_kw,
    u.avg_daily_kw,
    u.peak_kw,

    -- Rack utilization context. Not revenue directly but capacity signal (expansion or constraint risk) 
    r.avg_racks_used,
    r.max_racks_used,

    -- ERP revenue (enforcement layer), protected from NULLs. 
    -- Pull billed reveneue from ERP, but if no invoice exists that month, treat it as 0 instead of NULL.
    COALESCE(e.erp_revenue_total, 0) AS erp_revenue_total,
    COALESCE(e.erp_mrr, 0)          AS erp_mrr,
    COALESCE(e.erp_overage, 0)      AS erp_overage,
    COALESCE(e.erp_credits, 0)      AS erp_credits,

    -- Allocated energy cost (variable cost), protected from NULLs
    -- Allocate the monthly site power cost down to each contract version by usage share.
    -- If cost allocation isn’t present for some reason, default to 0 (so I can flag later).
    COALESCE(p.allocated_power_cost, 0) AS allocated_power_cost,

    -- Margin calculation (the convergence point). Margin = ERP revenue - allocated energy cost.
    -- This is the point where: contracts (revenue), Usage (cost driver), energy (variable cost) all converge.
    COALESCE(e.erp_revenue_total, 0) - COALESCE(p.allocated_power_cost, 0) AS gross_margin,

    -- Risk flags (why dashboards fail silently).
    -- late readings - data arrived after it was expected (timing drift).
    -- estimated readings - not final truth (accuracy risk)
    -- true-up - cost adjustments hitting later (reconciliation risk)
    u.late_reading_days,
    u.estimated_days,
    COALESCE(p.true_up_flag, 0) AS true_up_flag

FROM curated.v_usage_monthly u
JOIN curated.dim_contract c
    ON u.contract_id = c.contract_id
   AND u.contract_version = c.contract_version
LEFT JOIN curated.v_rack_monthly r
    ON u.contract_id = r.contract_id
   AND u.contract_version = r.contract_version
   AND u.usage_month = r.usage_month
LEFT JOIN curated.v_erp_revenue_monthly e
    ON u.contract_id = e.contract_id
   AND u.contract_version = e.contract_version
   AND u.usage_month = e.invoice_month
LEFT JOIN (
    SELECT *
    FROM mart.v_power_cost_allocated
    -- safety guard if I ever add more sites later
    -- WHERE site_id = 1
) p
    ON u.contract_id = p.contract_id
   AND u.contract_version = p.contract_version
   AND u.usage_month = p.usage_month;
GO

/* Wipe the MART clean, then rebuild a monthly contract-level truth table that ties contract structure + usage behavior
+ ERP revenue + allocated energy cost into a single reconciliable margin view, while preserving risk flags*/

-- Verification Check
SELECT COUNT(*) FROM mart.mart_contract_monthly;

SELECT TOP 10 *
FROM mart.mart_contract_monthly
ORDER BY month DESC, contract_id;

-- Row-count expectation. 1 row = contract × version × month. 8 customers.
-- Each customer has 1 contract, approx 60% have 2 contract versions, 24 months total, Version 2 only applies after amendment month
SELECT COUNT(*) AS mart_rows
FROM mart.mart_contract_monthly;

-- Null-risk check (revenue/cost). Contracts + ERP enforcement are aligned at the monthly grain.
-- Every MART row successfully found ERP revenue. 
-- joins between: v_usage_monthly & v_erp_revenue_monthly are structurally sound.
-- Physics (usage) and finance (cost) are time-aligned
SELECT
  SUM(CASE WHEN erp_revenue_total IS NULL THEN 1 ELSE 0 END) AS null_revenue_rows,
  SUM(CASE WHEN allocated_power_cost IS NULL THEN 1 ELSE 0 END) AS null_cost_rows
FROM mart.mart_contract_monthly;


/* This table clearly demonstrates: Contracts define bounds, Usage drives energy cost,
ERP enforces revenue but may drift, Margin emerges only after allocation, Risk is visible, not hidden.
The hard part isn’t billing racks, it’s keeping contracts, usage, energy, and finance from drifting out of alignment.*/
