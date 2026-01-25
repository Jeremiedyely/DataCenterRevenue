
import random #Creates controlled randomness to simulate real-world variability.
from datetime import date, timedelta
import pandas as pd
import sqlalchemy as sa

random.seed(42) #Locks the randomness so synthetic data realistic are repeatable.

OUT_DIR = r"C:\Users\jerem\project\DataCenterRevenue\raw"

#Define how much data + how messy it is.
num_customers = 8
contracts_per_customer = 1
start_date = date(2023, 1, 1)
end_date   = date(2024, 12, 31) #define begin/end of activity - creates 24 months of history (for trend analysis, contract amendemnts, reconciliation credibility)

late_rate = 0.08 #percentage of meter readings that arrive late. Late data is the #1 reason dashboards drift from ERP. 
est_rate  = 0.04 #Percentage of meter readings that are estimated. estimated usage: distorts cost allocation, creates margin risk, requires true-ups. This mirror real data center behavior 
dup_id_rate = 0.03 #Rate at which usage data references the wrong contract version. ( needed bc bad joins, version drift, contract amendments not synced) this is how revenue erros happen 

price_per_kw_range = (180, 450) #defines the range of revenue pricing. Flat pricing hides problems
power_kw_range = (5, 40) #how much power customers commit. (power commitment; drives revenue, drives cost allocation, drivres margin sensitivity) 
racks_range = (1, 10) 

#generate daily and monthly date sequences/orders.
def month_start(d: date) -> date: 
    return date(d.year, d.month, 1)

def daterange(start: date, end: date):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1) 

def monthrange(start: date, end: date):
    m = month_start(start)
    while m <= end:
        yield m
        y = m.year + (m.month // 12)
        mo = (m.month % 12) + 1
        m = date(y, mo, 1) 

        #creates the customer dimension table the root entity everything else attaches to. Output dim_customer.csv
customers = []
industries = ["AI Lab", "SaaS", "FinTech", "Healthcare", "Gaming", "E-commerce"]

for cid in range(1, num_customers + 1):
    customers.append({
        "customer_id": cid,
        "customer_name": f"Customer_{cid:02d}",
        "industry": random.choice(industries),
        "start_date": start_date
    })

df_customer = pd.DataFrame(customers)

#where revenue is born (contract structure + assumptions). output dim_contract.csv
#creates versioned customer contracts so revenue, usage, and billing can change over time without rewriting history.
contracts = []
contract_id = 100

for c in customers:
    for _ in range(contracts_per_customer):
        contract_id += 1
        racks_entitled = random.randint(*racks_range)
        power_commit_kw = round(random.uniform(*power_kw_range), 2)
        price_per_kw = round(random.uniform(*price_per_kw_range), 2)
        sla_tier = random.choice(["Standard", "Premium"])
        overage_allowed = random.choice([0, 1]) #Define capacity + pricing + rules. this where revenue is born

        # version 1. Store the original contract terms. Finance must preserve what was agreed at signing, even if it later changes.
        contracts.append({
            "contract_id": contract_id,
            "contract_version": 1,
            "customer_id": c["customer_id"],
            "effective_start": start_date,
            "effective_end": end_date,
            "racks_entitled": racks_entitled,
            "power_commit_kw": power_commit_kw,
            "price_per_kw": price_per_kw,
            "sla_tier": sla_tier,
            "overage_allowed_flag": overage_allowed
        })

        # contract amendment (version 2). customers renegotiate power, price, or both. realistic volatility that breaks naïve dashboards.
        amend_month = date(2024, random.randint(3, 10), 1)

        if random.random() < 0.6:
            new_power = round(power_commit_kw * random.uniform(0.9, 1.3), 2)
            new_price = round(price_per_kw * random.uniform(0.95, 1.2), 2) #Usage and cost change faster than finance expects.

            contracts[-1]["effective_end"] = amend_month - timedelta(days=1) #End Version 1 cleanly. to avoid overlapping contracts, double billing, failed reconciliations. 

            contracts.append({
                "contract_id": contract_id,
                "contract_version": 2,
                "customer_id": c["customer_id"],
                "effective_start": amend_month,
                "effective_end": end_date,
                "racks_entitled": racks_entitled,
                "power_commit_kw": new_power,
                "price_per_kw": new_price,
                "sla_tier": sla_tier,
                "overage_allowed_flag": overage_allowed
            })

df_contract = pd.DataFrame(contracts)

#Generate meter readings (RAW usage). where physics shows up and volatility appears. output fact_meter_power_daily.csv
meter_rows = []

for _, ctr in df_contract.iterrows():
    for d in daterange(ctr["effective_start"], ctr["effective_end"]):
        base = ctr["power_commit_kw"] * random.uniform(0.4, 1.05)
        used_kw = round(max(0, base + random.uniform(-1.5, 1.5)), 2)

        status = "on_time"
        if random.random() < late_rate:
            status = "late"
        elif random.random() < est_rate:
            status = "estimated"

        cid = int(ctr["contract_id"])
        cver = int(ctr["contract_version"])

        if random.random() < dup_id_rate:
            cver = 1 if cver == 2 else 2  #mismatch simulates: wrong contract version, misaligned joins, ERP vs usage mismatch. Most revenue leaks happen here

        meter_rows.append({
            "reading_date": d,
            "contract_id": cid,
            "contract_version": cver,
            "used_kw": used_kw,
            "reading_status": status,
            "ingested_at": pd.Timestamp.now()
        })

df_meter = pd.DataFrame(meter_rows)

rack_rows = []

for _, ctr in df_contract.iterrows():
    for d in daterange(ctr["effective_start"], ctr["effective_end"]):
        entitled = int(ctr["racks_entitled"])
        racks_used = max(0, min(entitled, int(round(entitled * random.uniform(0.6, 1.05)))))

        rack_rows.append({
            "usage_date": d,
            "contract_id": int(ctr["contract_id"]),
            "contract_version": int(ctr["contract_version"]),
            "racks_used": racks_used,
            "ingested_at": pd.Timestamp.now()
        })

df_racks = pd.DataFrame(rack_rows)

#ERP enforcement (what gets billed) to rpovide whether dashboards reconcile to billing. Generate invoice lines. Output fact_invoice_line.csv
inv_rows = []
invoice_id = 5000
line_id = 1

for m in monthrange(start_date, end_date):
    month_end = (m.replace(day=28) + timedelta(days=4))
    month_end = month_end - timedelta(days=month_end.day)

    for _, base_contract in df_contract.iterrows():
        if not (base_contract["effective_start"] <= month_end and base_contract["effective_end"] >= m):
            continue

        invoice_id += 1
        mrr = round(base_contract["power_commit_kw"] * base_contract["price_per_kw"], 2)

        inv_rows.append({
            "invoice_id": invoice_id,
            "invoice_line_id": line_id,
            "posting_date": month_end,
            "invoice_month": m,
            "contract_id": int(base_contract["contract_id"]),
            "contract_version": int(base_contract["contract_version"]),
            "revenue_type": "recurring",
            "amount": mrr
        })
        line_id += 1

        if random.random() < 0.08:
            credit = round(-random.uniform(200, 2500), 2)
            inv_rows.append({
                "invoice_id": invoice_id,
                "invoice_line_id": line_id,
                "posting_date": month_end,
                "invoice_month": m,
                "contract_id": int(base_contract["contract_id"]),
                "contract_version": int(base_contract["contract_version"]),
                "revenue_type": "credit",
                "amount": credit
            })
            line_id += 1

        if int(base_contract["overage_allowed_flag"]) == 1 and random.random() < 0.12:
            overage = round(random.uniform(200, 4000), 2)
            inv_rows.append({
                "invoice_id": invoice_id,
                "invoice_line_id": line_id,
                "posting_date": month_end,
                "invoice_month": m,
                "contract_id": int(base_contract["contract_id"]),
                "contract_version": int(base_contract["contract_version"]),
                "revenue_type": "overage",
                "amount": overage
            })
            line_id += 1

df_invoice = pd.DataFrame(inv_rows)

#Generate power cost monthly (variable cost). fact_power_cost_monthly.csv
cost_rows = []
site_id = 1

for m in monthrange(start_date, end_date):
    base_cost = random.uniform(180000, 420000)
    volatility = random.uniform(0.85, 1.25)
    total_cost = round(base_cost * volatility, 2)

    true_up = 1 if random.random() < 0.12 else 0

    cost_rows.append({
        "cost_month": m,
        "site_id": site_id,
        "total_power_cost": total_cost,
        "allocation_method": "kw_share",
        "true_up_flag": true_up
    })

df_cost = pd.DataFrame(cost_rows)

df_customer.to_csv(f"{OUT_DIR}\\dim_customer.csv", index=False)
df_contract.to_csv(f"{OUT_DIR}\\dim_contract.csv", index=False)
df_meter.to_csv(f"{OUT_DIR}\\fact_meter_power_daily.csv", index=False)
df_racks.to_csv(f"{OUT_DIR}\\fact_rack_utilization_daily.csv", index=False)
df_invoice.to_csv(f"{OUT_DIR}\\fact_invoice_line.csv", index=False)
df_cost.to_csv(f"{OUT_DIR}\\fact_power_cost_monthly.csv", index=False)

print("CSVs created in:", OUT_DIR)

#load into SQL Server Management Studio (SSMS)
SERVER = r"LAPTOP-QM8BIGC5\SQLEXPRESS02"
DB = "DataCenterRevenue"

conn_str = (
    "mssql+pyodbc://@"
    f"{SERVER}/{DB}"
    "?driver=ODBC+Driver+17+for+SQL+Server"
    "&trusted_connection=yes"
)

engine = sa.create_engine(conn_str, fast_executemany=True)

RAW_DIR = r"C:\Users\jerem\project\DataCenterRevenue\raw"

files_to_tables = {
    "dim_customer.csv": ("curated", "dim_customer"),
    "dim_contract.csv": ("curated", "dim_contract"),
    "fact_meter_power_daily.csv": ("raw", "fact_meter_power_daily"), #large data uploaded in SQL through BULK INSERT from folder 
    "fact_rack_utilization_daily.csv": ("raw", "fact_rack_utilization_daily"), #large data uploaded in SQL through BULK INSERT from folder 
    "fact_invoice_line.csv": ("raw", "fact_invoice_line"),
    "fact_power_cost_monthly.csv": ("raw", "fact_power_cost_monthly"), 
}

for filename, (schema, table) in files_to_tables.items():
    path = f"{RAW_DIR}\\{filename}"
    df = pd.read_csv(path)

    df.to_sql(
        name=table,
        con=engine,
        schema=schema,
        if_exists="append",
        index=False,
        chunksize=10_000
    )

    print(f"Loaded {filename} -> {schema}.{table} ({len(df):,} rows)")

print("All loads complete.")