Revenue-Critical Data Ownership System for Data Center Operations. Reduce risk and protect margin while ensuring data integrity. 
Objective: This project models how data center revenue and margin are actually created, stressed, and protected by explicitly tying together:
Contracts - Contract Versions - Racks - Usage - Energy - Margin

The goal is not reporting for reporting’s sake, but revenue integrity, ensuring financial outputs remain aligned with physical infrastructure, contractual commitments, and variable energy costs as they exist in reality.

Questions This System Answers

1. Where revenue is born
Contracts and estimator assumptions

2. Where revenue breaks
ERP configuration gaps and usage volatility

3. Why dashboards fail
Structural commitments (contracts, racks) drifting from behavioral reality (usage) without controls

Why This Project Exists
In infrastructure businesses, dashboards often lose trust because they:

Do not reconcile to ERP
Hide assumptions
Fail silently when data changes
Smooth or average highly variable costs like energy

This project demonstrates how to design a source-of-truth financial data model with explicit controls, so finance teams can:

Trust what they see
Understand why numbers move
Distinguish timing issues from real financial risk

Business Model: How Data Center Revenue Actually Works
Revenue (Predictable)

Created by contractual structure
Driven by: 
    - Rack entitlements
    - Reserved power (kW)
    - Pricing rules

Enforced through ERP invoices
Forms MRR (Monthly Recurring Revenue)

Cost (Volatile)
Driven primarily by energy
Energy cost reacts to usage behavior, not contract price
Usage volatility can erode margin if not structurally constrained

Core risk:
Revenue is fixed by contracts, but margin is exposed to usage-driven energy volatility.
This system exists to make that exposure visible, explainable, and controllable.

Architecture: End-to-End Ownership
Design Principles
Explicit business rules
Clear data grain
Auditability over convenience

Layered Design
Raw – Immutable inputs
Curated – Validated & controlled
Mart – Business truth
Presentation – Decision-making & controls

Data Layers
Raw (Immutable Inputs)
Represents system-of-record truth:

Meter readings (usage signals)
ERP invoices (financial enforcement)
Contracts (structure & entitlements)
Power cost feeds (variable cost input)

Curated (Validated & Staged)
This layer:
Cleans joins and keys
Handles late or missing data
Flags exceptions
Preserves auditability
Key features
Contract versioning for amendments
Late / estimated meter flags
Standardized customer and contract keys

Mart (Business Truth)
Answers finance questions, not technical ones.

Primary reporting table
Reporting grain:
      - Monthly by customer + contract

Includes:
Contracted racks and power
Used vs reserved power
Rack utilization
Allocated energy cost
Revenue
Margin
Risk-Weighted Metrics

Each metric is paired with assumptions, validation logic, and reconciliation checks.

Metric	                      Risk if Wrong
Contracted vs Used Power      Overbilling / customer disputes
Rack Utilization	      Capacity planning failure
MRR	                      Revenue misstatement
Customer Expansion	      False growth narrative
Power Cost Allocation	      Margin distortion
Margin by Customer	      Strategic pricing errors

Reconciliation & Controls (Trust Layer)
The goal is not just accuracy  it is trust.

Implemented via SQL and a dedicated Power BI “Controls & Data Integrity” page, including:

ERP totals vs Allocated Power totals
Variance percentage thresholds
Root-cause categorization (timing, mapping, missing/late data)
Reprocessing timestamp
Simulated sign-off status

This mirrors how finance teams evaluate data reliability.

Grain Design (Why Dashboards Fail Without This)
Defined explicitly:

Contract grain: one row per contract version
Meter grain: daily per contract
Rack utilization grain: daily per contract
Invoice grain: monthly per contract
Power cost grain: monthly per site (then allocated)

These grains answer the question:
"Which contracts, racks, and customers are profitable and which usage patterns are eroding margin through energy?"

Tools
SQL Server: transformations, business logic, reconciliation
Python: synthetic data generation and ingestion
Power BI: executive dashboards and controls

Outputs
Python: Generated raw datasets simulating real world failures:
Late data, Amendments, Usage volatility
SQL Server: Source-of-truth transformations, Allocation logic, Reconciliation and controls
Power BI: Revenue & Margin Overview and Revenue Controls & Reconciliation

Answers: 
"What did the company sell? Total Revenue"
"How stable is revenue? MRR"
"What did physics cost us? Allocated Power Cost"
"Are we actually making money? Gross Margin"

This project is designed to reflect how finance actually operates inside infrastructure-heavy businesses, where contracts promise revenue, but physics determines margin.

MOST OF MY SCRIPTS ARE AVAILABLE EXCEPTS: 
1. Mart Folder:  finance_close_recon (contains close simulation + cutoff logic + late posting smulation). It exposes how I simulated late ERP positing, recognized month rules (cutoff day logic), the "as-of close" revenue view logic. which is reusable.
2. Staging Folder: Staging (make raw data safe and joinable - clean, validated, and consisten grain)
3. Recon Folder: Reconciliation_erp_vs_mart_monthly ( it proves my dashboard numbers are real by reconciling erp truth to my modeled mart truth. month by month). It answers Do my dashboard totals tie to the ERP and explain variance.

