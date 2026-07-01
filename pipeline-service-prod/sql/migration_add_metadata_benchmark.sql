-- Migration: add extensible metadata and benchmark columns to pipeline_runs
-- Supports PostgreSQL (recommended) and Oracle (legacy)

-- POSTGRESQL (run as a DB admin / via psql)
-- Adds JSONB columns for flexible storage of script diagnostics and benchmark info
BEGIN;
ALTER TABLE pipeline_runs
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;
ALTER TABLE pipeline_runs
  ADD COLUMN IF NOT EXISTS benchmark JSONB;
-- Optional: GIN index for fast JSON queries
CREATE INDEX IF NOT EXISTS idx_pipeline_runs_metadata_gin ON pipeline_runs USING GIN (metadata);
CREATE INDEX IF NOT EXISTS idx_pipeline_runs_benchmark_gin ON pipeline_runs USING GIN (benchmark);
COMMIT;

-- ORACLE (run as a DBA or via SQL*Plus)
-- Oracle doesn't have JSONB; use CLOB and apply a JSON check for newer versions
-- This will add two CLOB columns and an optional JSON constraint when supported.
ALTER TABLE pipeline_runs ADD (metadata CLOB);
ALTER TABLE pipeline_runs ADD (benchmark CLOB);

-- If using Oracle 12.2+ you can add a constraint to validate JSON content:
-- ALTER TABLE pipeline_runs ADD CONSTRAINT metadata_is_json CHECK (metadata IS JSON);
-- ALTER TABLE pipeline_runs ADD CONSTRAINT benchmark_is_json CHECK (benchmark IS JSON);

-- Notes for application code:
-- * For Postgres, write Python dicts directly as JSON when inserting (e.g., psycopg2's json adaptation or SQLAlchemy JSON type).
-- * For Oracle, serialize dicts to JSON strings before binding into CLOB columns.

-- Example (Postgres) insert snippet:
-- INSERT INTO pipeline_runs (start_local,end_local,start_utc,end_utc,elapsed_seconds,elapsed_human,output_file,rowcount,log_file,pid,date_code,metadata,benchmark)
-- VALUES (:start_local,:end_local,:start_utc,:end_utc,:elapsed_seconds,:elapsed_human,:output_file,:rowcount,:log_file,:pid,:date_code,:metadata::jsonb,:benchmark::jsonb);

-- Example (Oracle) insert: bind JSON text for metadata/benchmark to CLOB columns.

-- Backfill guidance:
-- If you wish to backfill metadata/benchmark for existing rows, run an UPDATE statement to set defaults:
-- Postgres: UPDATE pipeline_runs SET metadata = '{}' WHERE metadata IS NULL;
-- Postgres: UPDATE pipeline_runs SET benchmark = '{}' WHERE benchmark IS NULL;
-- Oracle: UPDATE pipeline_runs SET metadata = '{}' WHERE metadata IS NULL;
-- Oracle: UPDATE pipeline_runs SET benchmark = '{}' WHERE benchmark IS NULL;

-- End of migration
