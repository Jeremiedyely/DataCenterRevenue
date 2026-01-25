SELECT
    s.name AS schema_name,
    v.name AS view_name
FROM sys.views v
JOIN sys.schemas s ON v.schema_id = s.schema_id
WHERE s.name = 'curated'
ORDER BY v.name;

SELECT COUNT(*) AS cnt FROM curated.v_meter_power_daily_effective;
SELECT COUNT(*) AS cnt FROM curated.v_rack_utilization_daily_effective;
SELECT COUNT(*) AS cnt FROM curated.v_usage_monthly;
SELECT COUNT(*) AS cnt FROM curated.v_rack_monthly;
SELECT COUNT(*) AS cnt FROM curated.v_erp_revenue_monthly;
SELECT COUNT(*) AS cnt FROM curated.v_power_cost_monthly;

-- v_meter_power_daily_effective 5,672 rows: confirm Usage is being filtered by legal contract windows.
-- v_rack_utilization_daily_effective 5,848 rows: confirm structure (racks) and behavior (usage) are independently modeled.
-- v_usage_monthly 192 rows: confirm Correct monthly aggregation No duplicate grain, No dropped months, No double counting
-- v_rack_monthly 192 rows: confirm monthly grain is consistent across physics (usage) and structure (racks). Help makes margin analysis trustworthy
-- v_erp_revenue_monthly 192 rows: confirm ERP data aligns to the same monthly grain. Revenue can now be reconciled against usage & cost. No hidden invoice duplication
-- v_power_cost_monthly 24 rows: confirm 24 months, 1 site, 1 row per month. what exacly allocation expect nexts. 

-- Overall: correct grain discipline, Contract version enforcement, separation of concerns, and Data trustworthiness 