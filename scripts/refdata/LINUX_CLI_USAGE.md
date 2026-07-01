# refdata_extract.py - Linux CLI Usage Guide

## Prerequisites

```bash
# Install required Python packages
pip install snowflake-connector-python pyodbc pyyaml

# Make script executable
chmod +x refdata_extract.py
```

## Basic Usage

### 1. Simple Run with Environment Variables

```bash
# Set credentials
export SNOW_USER="your_username"
export SNOW_PASSWORD="your_password"
export SNOW_SID="MART_SNOWFLAKE"

# Run with defaults
./refdata_extract.py --sql_file queries/products.sql
```

### 2. With Command Line Arguments

```bash
./refdata_extract.py myuser mypassword MART_SNOWFLAKE \
  --sql_file /path/to/query.sql
```

## Custom File Locations

### 3. All Custom Locations

```bash
./refdata_extract.py \
  --sql_file /opt/queries/product_extract.sql \
  --reference_data_dir /data/output/refdata \
  --archive_dir /data/archives/refdata \
  --log_dir /var/log/refdata \
  --log_file product_extract.log \
  --benchmark_log_dir /var/log/benchmarks \
  --output_prefix ProductData \
  --pipeline_name product_pipeline
```

**This creates:**
- Output: `/data/output/refdata/ProductData-20260212_143022.prod`
- Archive: `/data/archives/refdata/ProductData-20260212_143022.prod.gz`
- Log: `/var/log/refdata/product_extract.log`
- Benchmark: `/var/log/benchmarks/benchmark.jsonl`

### 4. Disable Archiving

```bash
./refdata_extract.py \
  --sql_file query.sql \
  --reference_data_dir /data/output \
  --archive_dir "" \
  --log_dir /var/log/myapp
```

### 5. Using Relative Paths

```bash
./refdata_extract.py \
  --sql_file ./queries/extract.sql \
  --reference_data_dir ./output \
  --archive_dir ./archives \
  --log_dir ./logs \
  --benchmark_log_dir ./benchmarks \
  --output_prefix MyExtract
```

## SQL Parameters

### 6. JSON Parameters (Inline)

```bash
./refdata_extract.py \
  --sql_file query.sql \
  --params_json '{"start_date":"2026-01-01","end_date":"2026-02-12","facility":"FAB1"}' \
  --reference_data_dir /data/output
```

### 7. JSON Parameters (File)

```bash
# Create params file
cat > params.json <<'EOF'
{
  "start_date": "2026-01-01",
  "end_date": "2026-02-12",
  "facility": "FAB1",
  "product_line": "AUTOMOTIVE"
}
EOF

# Run with params file
./refdata_extract.py \
  --sql_file query.sql \
  --params_file params.json \
  --reference_data_dir /data/output
```

## Advanced Connection Options

### 8. ODBC Connection

```bash
./refdata_extract.py \
  --source_odbc SNOWFLAKE_DSN \
  --source_warehouse COMPUTE_WH \
  --source_schema PROD_DB.PUBLIC \
  --sql_file query.sql \
  --reference_data_dir /data/output
```

### 9. Native Connector with Account

```bash
./refdata_extract.py myuser mypassword "" \
  --account xy12345.us-east-1 \
  --warehouse COMPUTE_WH \
  --role DATA_CONSUMER_ROLE \
  --source_schema PROD_DB.PUBLIC \
  --sql_file query.sql \
  --reference_data_dir /data/output
```

### 10. Secondary Roles

```bash
./refdata_extract.py \
  --role PRIMARY_ROLE \
  --secondary_roles ALL \
  --sql_file query.sql \
  --reference_data_dir /data/output
```

## Multi-Source Extraction

### 11. YAML Configuration File

```bash
# Create sources.yaml
cat > sources.yaml <<'EOF'
sources:
  - name: products
    output_prefix: ProductData
    reference_data_dir: /data/output/products
    archive_dir: /data/archives/products
    sql_file: queries/products.sql
    params:
      category: "ELECTRONICS"
    
  - name: orders
    output_prefix: OrderData
    reference_data_dir: /data/output/orders
    archive_dir: /data/archives/orders
    sql_file: queries/orders.sql
    params:
      start_date: "2026-01-01"
      end_date: "2026-02-12"
    
  - name: inventory
    output_prefix: InventoryData
    reference_data_dir: /data/output/inventory
    archive_dir: /data/archives/inventory
    sql_file: queries/inventory.sql
    source_warehouse: ANALYTICS_WH
    source_schema: WAREHOUSE_DB.INVENTORY
EOF

# Run multi-source extraction
./refdata_extract.py --sources_file sources.yaml
```

### 12. Multi-Output per Source

```bash
cat > multi_output.yaml <<'EOF'
sources:
  - name: sales_data
    source_warehouse: ANALYTICS_WH
    source_schema: SALES_DB.PUBLIC
    reference_data_dir: /data/output/sales
    archive_dir: /data/archives/sales
    outputs:
      - name: daily_sales
        output_prefix: DailySales
        sql_file: queries/daily_sales.sql
        params:
          date: "2026-02-12"
      
      - name: monthly_summary
        output_prefix: MonthlySummary
        sql_file: queries/monthly_summary.sql
        params:
          month: "2026-02"
      
      - name: quarterly_report
        output_prefix: QuarterlyReport
        sql_file: queries/quarterly_report.sql
        params:
          quarter: "Q1"
          year: "2026"
EOF

./refdata_extract.py --sources_file multi_output.yaml
```

### 13. JSON Multi-Source (Inline)

```bash
./refdata_extract.py --sources_json '[
  {
    "name": "source1",
    "sql_file": "query1.sql",
    "output_prefix": "Data1",
    "reference_data_dir": "/data/output/source1"
  },
  {
    "name": "source2",
    "sql_file": "query2.sql",
    "output_prefix": "Data2",
    "reference_data_dir": "/data/output/source2"
  }
]'
```

## Environment-Specific Configurations

### 14. Production Setup

```bash
./refdata_extract.py \
  --sql_file /opt/queries/prod_extract.sql \
  --reference_data_dir /apps/exensio_data/reference_data \
  --archive_dir /apps/exensio_data/archives-yms/reference_data/product \
  --log_dir /var/log/exensio/refdata \
  --log_file refdata_extract.log \
  --benchmark_log_dir /var/log/exensio/benchmarks \
  --output_prefix RefdataExtract \
  --pipeline_name refdata_production_pipeline \
  --environment prod \
  --log_level INFO
```

### 15. Development/Test Setup

```bash
./refdata_extract.py \
  --sql_file ~/dev/queries/test.sql \
  --reference_data_dir ~/dev/output \
  --archive_dir ~/dev/archives \
  --log_dir ~/dev/logs \
  --benchmark_log_dir ~/dev/benchmarks \
  --output_prefix TestData \
  --pipeline_name test_pipeline \
  --environment dev \
  --log_level DEBUG
```

## Custom Headers

### 16. Add Custom Header Line

```bash
./refdata_extract.py \
  --sql_file query.sql \
  --header "PRODUCT_ID|PRODUCT_NAME|PRICE|QUANTITY" \
  --reference_data_dir /data/output
```

## Automation & Scheduling

### 17. Cron Job Setup

```bash
# Edit crontab
crontab -e

# Add entry (runs daily at 2 AM)
0 2 * * * cd /opt/scripts/refdata && ./refdata_extract.py \
  --sql_file /opt/queries/daily_extract.sql \
  --reference_data_dir /data/output/daily \
  --archive_dir /data/archives/daily \
  --log_dir /var/log/refdata \
  --output_prefix DailyExtract \
  >> /var/log/refdata/cron.log 2>&1
```

### 18. Shell Script Wrapper

```bash
cat > run_refdata_extract.sh <<'EOF'
#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="/opt/scripts/refdata"
OUTPUT_DIR="/data/output/refdata"
ARCHIVE_DIR="/data/archives/refdata"
LOG_DIR="/var/log/refdata"
BENCHMARK_DIR="/var/log/benchmarks"

# Credentials from environment
export SNOW_USER="${SNOW_USER:-MFG_PRD_RPT_EXENSIO_USER}"
export SNOW_PASSWORD="${SNOW_PASSWORD}"
export SNOW_SID="${SNOW_SID:-MART_SNOWFLAKE}"

# Create directories
mkdir -p "$OUTPUT_DIR" "$ARCHIVE_DIR" "$LOG_DIR" "$BENCHMARK_DIR"

# Run extraction
cd "$SCRIPT_DIR"
./refdata_extract.py \
  --sql_file queries/product_extract.sql \
  --reference_data_dir "$OUTPUT_DIR" \
  --archive_dir "$ARCHIVE_DIR" \
  --log_dir "$LOG_DIR" \
  --benchmark_log_dir "$BENCHMARK_DIR" \
  --output_prefix ProductData \
  --pipeline_name product_extract_pipeline

echo "Extraction completed successfully"
EOF

chmod +x run_refdata_extract.sh
./run_refdata_extract.sh
```

### 19. Systemd Service

```bash
# Create service file
sudo cat > /etc/systemd/system/refdata-extract.service <<'EOF'
[Unit]
Description=Reference Data Extract Service
After=network.target

[Service]
Type=oneshot
User=exensio
Group=exensio
Environment="SNOW_USER=MFG_PRD_RPT_EXENSIO_USER"
Environment="SNOW_PASSWORD=your_password"
Environment="SNOW_SID=MART_SNOWFLAKE"
WorkingDirectory=/opt/scripts/refdata
ExecStart=/opt/scripts/refdata/refdata_extract.py \
  --sql_file /opt/queries/extract.sql \
  --reference_data_dir /data/output/refdata \
  --archive_dir /data/archives/refdata \
  --log_dir /var/log/refdata \
  --benchmark_log_dir /var/log/benchmarks \
  --output_prefix RefdataExtract

[Install]
WantedBy=multi-user.target
EOF

# Enable and run
sudo systemctl daemon-reload
sudo systemctl enable refdata-extract.service
sudo systemctl start refdata-extract.service
sudo systemctl status refdata-extract.service
```

### 20. Systemd Timer (Scheduled)

```bash
# Create timer file
sudo cat > /etc/systemd/system/refdata-extract.timer <<'EOF'
[Unit]
Description=Run Reference Data Extract Daily
Requires=refdata-extract.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable timer
sudo systemctl daemon-reload
sudo systemctl enable refdata-extract.timer
sudo systemctl start refdata-extract.timer
sudo systemctl list-timers refdata-extract.timer
```

## Monitoring & Logging

### 21. View Logs

```bash
# Tail main log
tail -f /var/log/refdata/refdata_extract.log

# View benchmark log
cat /var/log/benchmarks/benchmark.jsonl | jq .

# View last 10 benchmark entries
tail -10 /var/log/benchmarks/benchmark.jsonl | jq .

# Filter benchmarks by pipeline
cat /var/log/benchmarks/benchmark.jsonl | jq 'select(.pipeline_name == "product_pipeline")'
```

### 22. Check Output Files

```bash
# List output files
ls -lh /data/output/refdata/

# Count rows in output
wc -l /data/output/refdata/ProductData-*.prod

# View first 10 lines
head -10 /data/output/refdata/ProductData-*.prod

# Check archive
ls -lh /data/archives/refdata/*.gz
```

## Troubleshooting

### 23. Test Connection

```bash
# Test with minimal parameters
./refdata_extract.py \
  --sql_file test.sql \
  --reference_data_dir ./test_output \
  --archive_dir "" \
  --log_level DEBUG
```

### 24. Validate SQL File

```bash
# Create simple test query
cat > test_query.sql <<'EOF'
SELECT 'TEST' AS test_column;
EOF

./refdata_extract.py \
  --sql_file test_query.sql \
  --reference_data_dir /tmp/test \
  --archive_dir "" \
  --log_dir /tmp/logs
```

### 25. Debug Mode

```bash
./refdata_extract.py \
  --sql_file query.sql \
  --reference_data_dir /data/output \
  --log_level DEBUG \
  --log_dir /var/log/refdata 2>&1 | tee debug.log
```

## Password Handling

### 26. Using Environment Variables (Secure)

```bash
# Store in secure location
echo "export SNOW_PASSWORD='your_secure_password'" >> ~/.snowflake_creds
chmod 600 ~/.snowflake_creds

# Source before running
source ~/.snowflake_creds
./refdata_extract.py --sql_file query.sql --reference_data_dir /data/output
```

### 27. Using DW_PASSWORD Reference

```bash
# If password is "DW_PASSWORD", script looks for these env vars
export DW_PASS="actual_password"
# or
export YMS_PASSWORD="actual_password"
# or
export DW_PASSWORD="actual_password"

./refdata_extract.py myuser DW_PASSWORD MART_SNOWFLAKE \
  --sql_file query.sql \
  --reference_data_dir /data/output
```

## Complete Production Example

```bash
#!/bin/bash
# Production refdata extract script

# Environment setup
export SNOW_USER="MFG_PRD_RPT_EXENSIO_USER"
export SNOW_PASSWORD="${SNOWFLAKE_PROD_PASSWORD}"
export SNOW_SID="MART_SNOWFLAKE"

# Paths
BASE_DIR="/apps/exensio_data"
OUTPUT_DIR="${BASE_DIR}/reference_data"
ARCHIVE_DIR="${BASE_DIR}/archives-yms/reference_data/product"
LOG_DIR="/var/log/exensio/refdata"
BENCHMARK_DIR="/var/log/exensio/benchmarks"
QUERIES_DIR="/opt/queries/refdata"

# Create directories
mkdir -p "$OUTPUT_DIR" "$ARCHIVE_DIR" "$LOG_DIR" "$BENCHMARK_DIR"

# Run extraction with full configuration
/opt/scripts/refdata/refdata_extract.py \
  --sql_file "${QUERIES_DIR}/product_metadata.sql" \
  --reference_data_dir "$OUTPUT_DIR" \
  --archive_dir "$ARCHIVE_DIR" \
  --log_dir "$LOG_DIR" \
  --log_file "refdata_extract_$(date +%Y%m%d).log" \
  --benchmark_log_dir "$BENCHMARK_DIR" \
  --output_prefix "RefdataExtract" \
  --pipeline_name "refdata_production_pipeline" \
  --pipeline_type "batch" \
  --environment "prod" \
  --warehouse "application_prd_wh" \
  --role "APPLICATIONPRD_MFG_CONSUMER_RO" \
  --secondary_roles "ALL" \
  --log_level "INFO"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "Extraction completed successfully at $(date)"
    # Optional: Send success notification
else
    echo "Extraction failed with exit code $EXIT_CODE at $(date)"
    # Optional: Send alert
    exit $EXIT_CODE
fi
```

## Summary of Key Arguments

| Argument | Default | Example |
|----------|---------|---------|
| `--reference_data_dir` | `$REFERENCE_DATA_DIR` | `/data/output/refdata` |
| `--archive_dir` | `/apps/exensio_data/archives-yms/reference_data/product` | `/data/archives` |
| `--log_dir` | `./log` | `/var/log/refdata` |
| `--log_file` | `refdata_extract.log` | `extract_$(date +%Y%m%d).log` |
| `--benchmark_log_dir` | `./benchmark` | `/var/log/benchmarks` |
| `--output_prefix` | `RefdataExtract` | `ProductData` |
| `--pipeline_name` | `refdata_extract.py` | `my_pipeline` |
| `--environment` | Auto-detected | `prod`, `dev`, `test` |

## Output Files Generated

1. **Data File**: `{reference_data_dir}/{output_prefix}-{timestamp}.prod`
2. **Archive**: `{archive_dir}/{output_prefix}-{timestamp}.prod.gz`
3. **Log File**: `{log_dir}/{log_file}`
4. **Benchmark**: `{benchmark_log_dir}/benchmark.jsonl`
5. **Early Log**: `./log/early.log` (startup errors)

## Exit Codes

- `0` - Success
- `1` - Configuration/validation error
- `2` - Database/export error
- `3` - Uncaught exception

