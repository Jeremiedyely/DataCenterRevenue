Python
  ├─generate_dc_data.py

RAW
  ├─ Customers
  ├─ Contracts
  ├─ Meter Readings
  ├─ ERP Invoices
  └─ Power Cost Feeds
  
SQL/
DLL (SCHEMA)
  ├─ Monthly customer + contract grain
      
SQL/
CURATED(Staging)
  ├─ Validated joins
  ├─ Versioned contracts
  ├─ Late / estimated flags
        
SQL/
MART
  ├─ Monthly customer + contract grain
  ├─ Revenue, usage, cost, margin
        
SQL/
RECON
  ├─ ERP vs MART totals
  ├─ Variance thresholds
        
POWER BI
  ├─ Executive Metrics
  └─ Controls & Data Integrity
