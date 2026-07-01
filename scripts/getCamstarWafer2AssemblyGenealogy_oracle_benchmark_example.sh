#!/bin/bash
# Example: Running getCamstarWafer2AssemblyGenealogy.pl with Oracle benchmark persistence
#
# This script demonstrates how to configure the Perl script to write benchmark
# data to an Oracle database instead of (or in addition to) the JSONL file.
#
# Prerequisites:
# 1. Oracle database with pipeline_runs table created (see pipeline-service-prod/sql/create_pipeline_runs.sql)
# 2. Migration applied for metadata/benchmark columns (see pipeline-service-prod/sql/migration_add_metadata_benchmark.sql)
# 3. Oracle client libraries installed (for DBD::Oracle)
# 4. TNS configuration or Oracle connection string available

# Option 1: Use default credentials (recommended for standard setup)
# Just pass --benchmark_db_user flag without a value to use:
#   Username: refdb
#   Password: br#^gox66312sdAB

# Option 2: Set custom credentials via environment variables
export BENCHMARK_DB_USER="your_db_user"
export BENCHMARK_DB_PASS="your_db_password"

# Option 3: Pass custom credentials via command line (less secure, visible in process list)
# Use --benchmark_db_user "username" and --benchmark_db_pass "password" flags

# Oracle DSN can be:
# - TNS name (e.g., "DWPRD", "LOTGPRD")
# - Full connection string (e.g., "//hostname:1521/service_name")

# Example 1: Use default credentials (simplest method)
perl scripts/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db CEBU \
  --source_warehouse application_prd_wh \
  --source_schema ANALYTICSPRD.FCS \
  --start_hours 2 \
  --end_hours 0 \
  --out_gen ./output/gen \
  --archive_gen ./archive/gen \
  --out_trace ./output/trace \
  --archive_trace ./archive/trace \
  --logfile ./log/getCamstarWafer2AssemblyGenealogy.log \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user \
  --pipeline_name "camstar_wafer2assembly_cebu" \
  --pipeline_type "batch"

# Example 2: Write to both JSONL file AND Oracle database with custom credentials
perl scripts/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db OSV \
  --source_warehouse application_prd_wh \
  --source_schema ANALYTICSPRD.FCS \
  --start_hours 2 \
  --end_hours 0 \
  --out_gen ./output/gen \
  --archive_gen ./archive/gen \
  --out_trace ./output/trace \
  --archive_trace ./archive/trace \
  --logfile ./log/getCamstarWafer2AssemblyGenealogy.log \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn DWPRD \
  --benchmark_db_user "custom_user" \
  --benchmark_db_pass "custom_password" \
  --pipeline_name "camstar_wafer2assembly_osv" \
  --pipeline_type "batch"

# Example 3: Write ONLY to Oracle database with default credentials (omit --benchmark_log)
perl scripts/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db ONSZ \
  --source_warehouse application_prd_wh \
  --source_schema ANALYTICSPRD.FCS \
  --start_hours 24 \
  --end_hours 0 \
  --out_gen ./output/gen \
  --archive_gen ./archive/gen \
  --out_trace ./output/trace \
  --archive_trace ./archive/trace \
  --logfile ./log/getCamstarWafer2AssemblyGenealogy_onsz.log \
  --benchmark_db_dsn "//oracle-server.example.com:1521/PRODDB" \
  --benchmark_db_user \
  --pipeline_name "camstar_wafer2assembly_onsz" \
  --pipeline_type "batch"

# Example 4: Using TNS name with environment variables
export BENCHMARK_DB_USER="pipeline_writer"
export BENCHMARK_DB_PASS="$(cat /secure/oracle_password.txt)"

perl scripts/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db SBN \
  --source_warehouse application_prd_wh \
  --source_schema ANALYTICSPRD.FCS \
  --start_hours 4 \
  --end_hours 0 \
  --out_gen ./output/gen \
  --archive_gen ./archive/gen \
  --out_trace ./output/trace \
  --archive_trace ./archive/trace \
  --logfile ./log/getCamstarWafer2AssemblyGenealogy_sbn.log \
  --benchmark_log ./log/benchmark.jsonl \
  --benchmark_db_dsn LOTGPRD \
  --pipeline_name "camstar_wafer2assembly_sbn" \
  --pipeline_type "batch" \
  --lock_file ./log/camstar_sbn.lock

# Notes:
# - If BENCHMARK_DB_DSN is not provided, only JSONL logging occurs
# - If --benchmark_db_user is passed without a value, default credentials are used (refdb/br#^gox66312sdAB)
# - If BENCHMARK_DB_USER/PASS env vars or explicit values are not provided, Oracle insert is skipped with a warning
# - The script will continue even if Oracle insert fails (non-blocking)
# - Both JSONL and Oracle can be used simultaneously for redundancy
# - Environment variable PIPELINE_ENV can override environment detection (prod/qa/dev)
