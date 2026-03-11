⚠️ Note "Some of the table/view scripts are not included in this repository folder.  
The underlying logic can still be reused and recreated from the documentation in this project.  
Certain implementation details were intentionally not published to keep the repository focused on the system architecture and core logic.

Ptoject : Preventing Revenue Drift to Protect Data Center Margins - Revenue Control System Data Flow ownership

This system enforces a single critical rule:

Infrastructure reality
must equal
financial reporting

If the two diverge, the system detects and explains the variance.

• Problem the System Solves:

In data centers, revenue depends on several layers staying aligned.
Contracts
    ↓
Infrastructure capacity
    ↓
Power usage
    ↓
Energy costs
    ↓
ERP billing
    ↓
Financial reporting

If any layer drifts, problems occur.

Examples:
	•	Contract amendments not reflected in billing
	•	Usage spikes not captured in invoices
	•	Late meter readings
	•	ERP configuration errors
	•	Incorrect energy cost allocation

Consequences:
	•	Customer overbilling
	•	Revenue leakage
	•	Margin distortion
	•	Financial close surprises

This system prevents revenue drift.

• Purpose of the System:

The purpose is to enforce alignment between:

PHYSICS
(power usage, racks, infrastructure)

and

FINANCE
(invoices, revenue, margin)

The system ensures:
	•	Revenue is explainable
	•	Margins are measurable
	•	Errors are detectable
	•	Finance can trust reported numbers

The architecture follows several core principles.

Rule 1 — Physics Cannot Be Overridden
Energy consumption is real.
Contracts and ERP systems cannot override infrastructure reality.
Power usage → drives cost

Rule 2 — Structure Controls Behavior
Contracts define the structural limits of usage.
contract → racks → power_commit_kw

Rule 3 — Grain Defines Truth
Every dataset must have a clearly defined grain.

Example: 
meter readings = daily per contract
invoices = monthly per contract
reporting = monthly per contract
Without grain control, data becomes unreliable.

Rule 4 — Reconciliation Builds Trust
Finance only trusts numbers that reconcile.
ERP totals
vs
Model totals
Variance must always be explainable.

Rule 5 — Assumptions Must Be Visible
Revenue systems rely on assumptions.

Examples:
	•	power allocation logic
	•	revenue timing
	•	margin calculation rules

All assumptions must be documented.

The architecture consists of four layers.
RAW
↓
CURATED
↓
MART
↓
CONTROLS & PRESENTATION

Layer 1 — Raw Data (Immutable)
Purpose:Capture source events exactly as they occur.
Raw data represents operational reality:
	•	contracts
	•	infrastructure usage
	•	invoices
	•	energy costs

Layer 2 — Curated Layer
Purpose:Clean and standardize raw data for consistent analysis.
Tasks performed:
	•	remove duplicates
	•	normalize contract versions
	•	handle late data
	•	aggregate daily → monthly

Layer 3 — Mart Layer
Purpose:Build the analytical business model.
Primary table:mart_contract_monthly
Grain: contract_id, contract_version, month
Metrics: 

total_kw
avg_daily_kw
peak_kw
avg_racks_used

erp_revenue_total
allocated_power_cost
gross_margin

late_reading_days
estimated_days

This represents the financial model of operations.

Layer 4 — Controls Layer
Purpose:Ensure financial integrity and detect anomalies.
Tables / Views:
recon_erp_vs_mart_monthly
v_controls_data_integrity
v_controls_summary
v_contract_exceptions_only

These controls detect:
	•	revenue variance
	•	late meter readings
	•	estimated data usage
	•	contract amendments
	•	negative margin conditions
This layer functions as the finance safety system.


System Inputs:

The system ingests four categories of data;

• Contract Data - Defines customer entitlement:

contract_id
racks_entitled
power_commit_kw
price_per_kw

• Usage Data - Measures infrastructure consumption:

meter readings
rack utilization

• ERP Billing Data - Represents financial transactions:

invoice lines
credits
overages

• Cost Data: Represents operating costs:
power cost
allocation logic

System Processes: 
The system performs several key transformations.

Usage Aggregation:
daily meter readings
→ monthly usage metrics

Calculated metrics:
total_kw
avg_daily_kw
peak_kw

Revenue Modeling - From ERP invoices:
recurring revenue
overage revenue
credits

Aggregated to monthly totals.

Power Cost Allocation:
Energy cost is allocated proportionally.
Example formula: gross_margin = revenue − allocated_power_cost

Margin Calculation: 
gross_margin = revenue − allocated_power_cost

Reconciliation - Compare two systems:
ERP revenue
vs
modeled revenue

Outputs:
variance_amount
variance_pct
control_status

System Outputs: 

The system produces two categories of outputs:

Operational Insights

Executive dashboard metrics:
	•	revenue trends
	•	margin trends
	•	contract utilization
	•	power usage patterns


Financial Controls

Controls dashboard provides:
	•	ERP vs model variance
	•	late data alerts
	•	contract amendment true-ups
	•	negative margin detection

These outputs support:

Finance
Operations
Executives
Revenue assurance

This system enforces a single critical rule: 
Infrastructure reality
must equal
financial reporting

If the two diverge, the system detects and explains the variance.

This project is not simply a dashboard. It is a Revenue Integrity System.