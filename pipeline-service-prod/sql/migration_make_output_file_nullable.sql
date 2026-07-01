-- Migration: Make output_file column nullable in pipeline_runs table
-- This supports multi-file pipelines where a single representative file may not exist
-- Scripts will use 'N/A' as a fallback value for consistency, but NULL is also allowed

-- ORACLE
-- Make output_file nullable
ALTER TABLE pipeline_runs MODIFY (output_file VARCHAR2(1024) NULL);

-- Optional: Update existing empty/placeholder values to NULL for consistency
-- UPDATE pipeline_runs SET output_file = NULL WHERE output_file = '' OR output_file = 'N/A';
-- COMMIT;

-- POSTGRESQL (if needed in future)
-- ALTER TABLE pipeline_runs ALTER COLUMN output_file DROP NOT NULL;

-- Notes:
-- * For single-file pipelines: output_file contains the actual file path
-- * For multi-file pipelines: output_file contains the first/representative file or 'N/A'
-- * The complete list of files is always in output_files_trace or out_files arrays
-- * Scripts will default to 'N/A' when no representative file exists, but NULL is acceptable

-- End of migration
