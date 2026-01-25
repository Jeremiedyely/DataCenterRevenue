CREATE DATABASE DataCenterRevenue;
GO

USE DataCenterRevenue;
GO

-- ownership boundaries
CREATE SCHEMA raw;
GO
CREATE SCHEMA curated;
GO
CREATE SCHEMA mart;
GO
CREATE SCHEMA recon;
GO

-- core dimension tables (structure = revenue anchor)
CREATE TABLE curated.dim_customer (
    customer_id INT NOT NULL,
    customer_name VARCHAR(100) NOT NULL,
    industry VARCHAR(50) NULL,
    start_date DATE NOT NULL,
    CONSTRAINT pk_client PRIMARY KEY (customer_id)
);
-- dimension contract (versioned = real-world credibility)
CREATE TABLE curated.dim_contract (
    contract_id INT NOT NULL,
    contract_version INT NOT NULL,
    customer_id INT NOT NULL,
    effective_start DATE NOT NULL,
    effective_end DATE NOT NULL,
    racks_entitled INT NOT NULL, -- number racks client contractually granted to use
    power_commit_kw DECIMAL(10,2) NOT NULL, -- amnt power contractually reserved for client
    price_per_kw DECIMAL(10,2) NOT NULL,
    sla_tier VARCHAR(20) NOT NULL, -- service guarantee promised to client
    overage_allowed_flag BIT NOT NULL, -- is client allowed to exceed contracted capacity
    CONSTRAINT pk_dim_contract PRIMARY KEY (contract_id, contract_version),
    CONSTRAINT fk_contract_customer FOREIGN KEY (customer_id) REFERENCES curated.dim_customer(customer_id)
);
-- FACT tables (behavior + cost) metered power (usage = volatility)
CREATE TABLE raw.fact_meter_power_daily (
    reading_date DATE NOT NULL, -- when was meter measurement captured 
    contract_id INT NOT NULL,
    contract_version INT NOT NULL,
    used_kw DECIMAL(10,2) NULL,
    reading_status VARCHAR(20) NOT NULL, -- on_time / late / estimated
    ingested_at DATETIME2(0) NOT NULL,-- timestamp
    CONSTRAINT pk_fact_meter_power_daily PRIMARY KEY (reading_date, contract_id, contract_version)
);
-- Rack utilization
CREATE TABLE raw.fact_rack_utilization_daily (
    usage_date DATE NOT NULL,
    contract_id INT NOT NULL,
    contract_version INT NOT NULL,
    racks_used INT NULL,
    ingested_at DATETIME2(0) NOT NULL,
    CONSTRAINT pk_fact_rack_utilization_daily PRIMARY KEY (usage_date, contract_id, contract_version)
);
-- ERP invoice lines (where revenue is enforced)
CREATE TABLE raw.fact_invoice_line (
    invoice_id INT NOT NULL,
    invoice_line_id INT NOT NULL,
    posting_date DATE NOT NULL,
    invoice_month DATE NOT NULL,
    contract_id INT NOT NULL,
    contract_version INT NOT NULL,
    revenue_type VARCHAR(20) NOT NULL, -- recurring / overage / credit
    amount DECIMAL(12,2) NOT NULL,
    CONSTRAINT pk_fact_invoice_line PRIMARY KEY (invoice_id, invoice_line_id)
);
-- Power cost (variable cost)
CREATE TABLE raw.fact_power_cost_monthly (
    cost_month DATE NOT NULL,
    site_id INT NOT NULL,
    total_power_cost DECIMAL(14,2) NULL,
    allocation_method VARCHAR(50) NOT NULL, -- distrube tpc across client/contract
    true_up_flag BIT NOT NULL, -- reconcile estimates with actuals
    CONSTRAINT pk_fact_power_cost_monthly PRIMARY KEY (cost_month, site_id) -- pc settle montly site level enforces business grain and prevents cost duplication
);


-- verification query after execution 
SELECT 
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name IN ('raw','curated','mart','recon')
ORDER BY s.name, t.name;

 -- validate PK
SELECT 
    s.name AS schema_name,
    t.name AS table_name,
    kc.name AS constraint_name
FROM sys.key_constraints kc
JOIN sys.tables t ON kc.parent_object_id = t.object_id
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE kc.type = 'PK'
ORDER BY s.name, t.name;
