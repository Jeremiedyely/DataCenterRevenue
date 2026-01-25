-- Total monthly usage (all contracts)
CREATE VIEW mart.v_total_usage_monthly AS
SELECT
    usage_month,
    SUM(total_kw) AS total_site_kw
FROM curated.v_usage_monthly
GROUP BY usage_month;
GO

-- Allocate power cost per contract. Energy follows usage not contracts. 
-- True ups flow into margin transparently. No averaging. 
CREATE VIEW mart.v_power_cost_allocated AS
SELECT
    u.contract_id,
    u.contract_version,
    u.usage_month,
    u.total_kw,
    t.total_site_kw,
    pc.total_power_cost,
    pc.true_up_flag,
    CASE 
        WHEN t.total_site_kw = 0 THEN 0
        ELSE (u.total_kw / t.total_site_kw) * pc.total_power_cost
    END AS allocated_power_cost
FROM curated.v_usage_monthly u
JOIN mart.v_total_usage_monthly t
    ON u.usage_month = t.usage_month
JOIN curated.v_power_cost_monthly pc
    ON u.usage_month = pc.cost_month;
GO
