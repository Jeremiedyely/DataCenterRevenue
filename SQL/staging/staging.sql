-- Contract effective daily usage. Usage must respect contract versions or revenue breaks silently.
-- Enforce legal contract boundaries. Prevent usage from floating across amendments. 
-- Creates a reading set that includes late and on-time data with traceable causes.

CREATE VIEW curated.v_meter_power_daily_effective AS
SELECT
    m.reading_date,
    m.contract_id,
    m.contract_version,
    m.used_kw,
    m.reading_status,
    m.ingested_at
FROM raw.fact_meter_power_daily m
JOIN curated.dim_contract c
    ON m.contract_id = c.contract_id
   AND m.contract_version = c.contract_version
   AND m.reading_date BETWEEN c.effective_start AND c.effective_end;
GO
-- Contract effectiv daily rack usage (structure constraint, not revenue but capacity signal). 
-- Use later to explain utilization & expansion risk
CREATE VIEW curated.v_rack_utilization_daily_effective AS
SELECT
    r.usage_date,
    r.contract_id,
    r.contract_version,
    r.racks_used,
    r.ingested_at
FROM raw.fact_rack_utilization_daily r
JOIN curated.dim_contract c
    ON r.contract_id = c.contract_id
   AND r.contract_version = c.contract_version
   AND r.usage_date BETWEEN c.effective_start AND c.effective_end;
GO
-- Montlhy usage aggregation physics - finance. Physic is respected, not averaged blindly
-- Daily volatility collapse - monthly finance grain. Late/estimated readings preserved as risk flags.
CREATE VIEW curated.v_usage_monthly AS
SELECT
    contract_id,
    contract_version,
    DATEFROMPARTS(
        DATEPART(YEAR, reading_date),
        DATEPART(MONTH, reading_date),
        1
    ) AS usage_month,
    AVG(used_kw)        AS avg_daily_kw,
    MAX(used_kw)        AS peak_kw,
    SUM(used_kw)        AS total_kw,
    SUM(CASE WHEN reading_status = 'late' THEN 1 ELSE 0 END) AS late_reading_days,
    SUM(CASE WHEN reading_status = 'estimated' THEN 1 ELSE 0 END) AS estimated_days
FROM curated.v_meter_power_daily_effective
GROUP BY
    contract_id,
    contract_version,
    DATEFROMPARTS(YEAR(reading_date), MONTH(reading_date), 1);
GO
-- Monthly rack utlization. Show how much contract-defined rack capacity the customer is allowed to consume.
-- Explain expansion (revenue opportunity), Congestion (operational + revenue risk) and Capacity planning risk (capital allocation risk)  
CREATE VIEW curated.v_rack_monthly AS
SELECT
    contract_id,
    contract_version,
    DATEFROMPARTS(YEAR(usage_date), MONTH(usage_date), 1) AS usage_month,
    AVG(racks_used * 1.0) AS avg_racks_used, -- enforce decimal to prevent silent rounding errors
    MAX(racks_used)       AS max_racks_used
FROM curated.v_rack_utilization_daily_effective
GROUP BY
    contract_id,
    contract_version,
    DATEFROMPARTS(YEAR(usage_date), MONTH(usage_date), 1);
GO
-- ERP revenue normalization (monthly) - Enforcement not truth. 
-- Normalize before reconciling and preserve revenue type (no dangerous netting).
CREATE VIEW curated.v_erp_revenue_monthly AS
SELECT
    contract_id,
    contract_version,
    invoice_month,
    SUM(amount) AS erp_revenue_total,
    SUM(CASE WHEN revenue_type = 'recurring' THEN amount ELSE 0 END) AS erp_mrr,
    SUM(CASE WHEN revenue_type = 'overage'   THEN amount ELSE 0 END) AS erp_overage,
    SUM(CASE WHEN revenue_type = 'credit'    THEN amount ELSE 0 END) AS erp_credits
FROM raw.fact_invoice_line
GROUP BY
    contract_id,
    contract_version,
    invoice_month;
GO
-- Monthly power cost allocation base. 
-- Allocation happens in the MART.
CREATE VIEW curated.v_power_cost_monthly AS
SELECT
    cost_month,
    site_id,
    total_power_cost,
    allocation_method,
    true_up_flag
FROM raw.fact_power_cost_monthly;
GO
