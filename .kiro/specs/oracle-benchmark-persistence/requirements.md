# Requirements Document: Oracle Benchmark Persistence

## Introduction

This specification defines the requirements for adding Oracle database persistence capabilities to the `getCamstarWafer2AssemblyGenealogy.pl` script's benchmark logging system. The script currently supports writing benchmark metrics to JSONL files. This enhancement adds the ability to write benchmark data directly to an Oracle database table (`pipeline_runs`) for centralized monitoring, querying, and analysis.

## Glossary

- **Benchmark Data**: Performance metrics and diagnostic counters collected during pipeline execution
- **JSONL**: JSON Lines format - newline-delimited JSON records
- **Oracle DSN**: Data Source Name - TNS name or connection string for Oracle database
- **pipeline_runs**: Oracle database table storing pipeline execution metrics
- **Default Credentials**: Pre-configured username/password used when flag is passed without explicit value
- **Dual Persistence**: Writing benchmark data to both JSONL file and Oracle database simultaneously
- **Non-blocking**: Oracle failures do not prevent pipeline execution from completing successfully
- **CLOB**: Character Large Object - Oracle data type for storing large text/JSON data
- **Diagnostic Counters**: Metrics tracking data flow (rows_fetched, rows_kept, rows_skipped)

## Requirements

### Requirement 1: Oracle Database Connection Configuration

**User Story:** As a data engineer, I want to configure Oracle database connection parameters via command-line arguments, so that the script can connect to Oracle to persist benchmark data.

#### Acceptance Criteria

1. WHEN `--benchmark_db_dsn` parameter is provided, THE script SHALL accept TNS names (e.g., "DWPRD", "LOTGPRD")
2. WHEN `--benchmark_db_dsn` parameter is provided, THE script SHALL accept full connection strings (e.g., "//hostname:1521/service_name")
3. WHEN `--benchmark_db_user` parameter is provided with a value, THE script SHALL use the provided username
4. WHEN `--benchmark_db_pass` parameter is provided with a value, THE script SHALL use the provided password
5. WHEN `--benchmark_db_dsn` is not provided, THE script SHALL skip Oracle persistence and continue execution

### Requirement 2: Default Credentials Support

**User Story:** As a data engineer, I want to use default credentials by passing a flag without a value, so that I can simplify pipeline configuration in standard environments.

#### Acceptance Criteria

1. WHEN `--benchmark_db_user` flag is passed without a value, THE script SHALL use username "refdb"
2. WHEN `--benchmark_db_user` flag is passed without a value, THE script SHALL use password "br#^gox66312sdAB"
3. WHEN default credentials are used, THE script SHALL log "Using default benchmark database credentials (user: refdb)"
4. WHEN `--benchmark_db_user` has an explicit value, THE script SHALL NOT use default credentials
5. WHEN `--benchmark_db_user` flag is not present, THE script SHALL check environment variables before using defaults

### Requirement 3: Environment Variable Credential Support

**User Story:** As a security-conscious engineer, I want to provide credentials via environment variables, so that passwords are not visible in command-line arguments or process lists.

#### Acceptance Criteria

1. WHEN `BENCHMARK_DB_USER` environment variable is set, THE script SHALL use it if no command-line value provided
2. WHEN `BENCHMARK_DB_PASS` environment variable is set, THE script SHALL use it if no command-line value provided
3. WHEN both command-line and environment variables are provided, THE script SHALL prioritize command-line values
4. WHEN neither command-line nor environment variables are provided, THE script SHALL use default credentials if flag is present
5. WHEN no credentials are available, THE script SHALL skip Oracle persistence with a warning

### Requirement 4: Credential Resolution Priority

**User Story:** As a data engineer, I want clear credential resolution order, so that I can predict which credentials will be used in different scenarios.

#### Acceptance Criteria

1. THE script SHALL resolve credentials in this order: (1) Command-line explicit values, (2) Environment variables, (3) Default credentials, (4) Skip Oracle
2. WHEN multiple credential sources exist, THE script SHALL use the highest priority source
3. WHEN credential resolution completes, THE script SHALL log which method was used (except for passwords)
4. WHEN default credentials are selected, THE script SHALL explicitly log this decision
5. WHEN Oracle is skipped due to missing credentials, THE script SHALL log a warning message

### Requirement 5: Oracle Database Connection

**User Story:** As a data engineer, I want the script to establish Oracle database connections using DBI, so that benchmark data can be inserted into the pipeline_runs table.

#### Acceptance Criteria

1. WHEN Oracle credentials are available, THE script SHALL attempt to connect using DBI with "dbi:Oracle:$dsn"
2. WHEN connection succeeds, THE script SHALL set AutoCommit to 0 (manual commit mode)
3. WHEN connection succeeds, THE script SHALL set RaiseError to 1 (exception on errors)
4. WHEN connection fails, THE script SHALL log a warning and continue execution
5. WHEN connection fails, THE script SHALL NOT terminate the pipeline

### Requirement 6: Benchmark Data Insertion

**User Story:** As a data engineer, I want benchmark data inserted into the pipeline_runs table, so that I can query and analyze pipeline performance centrally.

#### Acceptance Criteria

1. WHEN Oracle connection succeeds, THE script SHALL prepare an INSERT statement for pipeline_runs table
2. WHEN inserting data, THE script SHALL bind all required parameters (timestamps, metrics, file paths)
3. WHEN inserting data, THE script SHALL serialize array fields to JSON for CLOB columns
4. WHEN insert succeeds, THE script SHALL commit the transaction
5. WHEN insert succeeds, THE script SHALL log "Benchmark data inserted into Oracle pipeline_runs table"

### Requirement 7: Diagnostic Counter Storage

**User Story:** As a data engineer, I want diagnostic counters stored in the metadata JSON column, so that I can analyze data quality and processing efficiency.

#### Acceptance Criteria

1. WHEN inserting benchmark data, THE script SHALL create a metadata JSON object
2. THE metadata JSON SHALL contain "rows_fetched" (total rows from source database)
3. THE metadata JSON SHALL contain "rows_kept" (rows successfully processed)
4. THE metadata JSON SHALL contain "rows_skipped" (rows that failed validation)
5. THE metadata JSON SHALL be stored in the "metadata" CLOB column

### Requirement 8: File Path Tracking

**User Story:** As a data engineer, I want output file paths stored in the database, so that I can trace which files were generated by each pipeline run.

#### Acceptance Criteria

1. WHEN inserting benchmark data, THE script SHALL store genealogy output file path in "output_file_gen"
2. WHEN inserting benchmark data, THE script SHALL serialize genealogy file array to JSON in "output_files_gen" CLOB
3. WHEN inserting benchmark data, THE script SHALL store trace output file path in "output_file_trace"
4. WHEN inserting benchmark data, THE script SHALL serialize trace file array to JSON in "output_files_trace" CLOB
5. WHEN inserting benchmark data, THE script SHALL serialize archived file arrays to JSON in respective CLOB columns

### Requirement 9: Timestamp Handling

**User Story:** As a data engineer, I want accurate timestamps in both local and UTC formats, so that I can analyze pipeline execution across time zones.

#### Acceptance Criteria

1. WHEN inserting benchmark data, THE script SHALL store start_local timestamp in "YYYY-MM-DD HH24:MI:SS" format
2. WHEN inserting benchmark data, THE script SHALL store end_local timestamp in "YYYY-MM-DD HH24:MI:SS" format
3. WHEN inserting benchmark data, THE script SHALL convert ISO 8601 UTC timestamps to Oracle format
4. WHEN inserting benchmark data, THE script SHALL store start_utc and end_utc as TIMESTAMP columns
5. WHEN inserting benchmark data, THE script SHALL store elapsed_seconds as numeric and elapsed_human as string

### Requirement 10: Non-Blocking Error Handling

**User Story:** As a pipeline operator, I want Oracle failures to not stop pipeline execution, so that data processing continues even if benchmark logging fails.

#### Acceptance Criteria

1. WHEN Oracle connection fails, THE script SHALL log a warning and continue execution
2. WHEN Oracle insert fails, THE script SHALL rollback the transaction
3. WHEN Oracle insert fails, THE script SHALL log a warning with error details
4. WHEN Oracle insert fails, THE script SHALL continue to pipeline completion
5. WHEN Oracle insert fails, THE script SHALL still exit with status 0 (success)

### Requirement 11: Dual Persistence Mode

**User Story:** As a data engineer, I want to write benchmark data to both JSONL and Oracle simultaneously, so that I have redundancy during migration and rollback capability.

#### Acceptance Criteria

1. WHEN both `--benchmark_log` and `--benchmark_db_dsn` are provided, THE script SHALL write to both destinations
2. WHEN JSONL write succeeds and Oracle fails, THE script SHALL continue execution
3. WHEN JSONL write fails and Oracle succeeds, THE script SHALL continue execution
4. WHEN both writes succeed, THE script SHALL log success for both
5. WHEN only one destination is configured, THE script SHALL write only to that destination

### Requirement 12: Backward Compatibility

**User Story:** As a pipeline operator, I want existing pipelines to work without changes, so that I can adopt Oracle persistence gradually.

#### Acceptance Criteria

1. WHEN no Oracle parameters are provided, THE script SHALL behave exactly as before (JSONL only)
2. WHEN only `--benchmark_log` is provided, THE script SHALL write only to JSONL file
3. WHEN existing command-line arguments are used, THE script SHALL not require any changes
4. WHEN Oracle parameters are added, THE script SHALL not break existing functionality
5. WHEN Oracle parameters are removed, THE script SHALL revert to JSONL-only mode

### Requirement 13: Environment Detection

**User Story:** As a data engineer, I want the script to automatically detect the environment (prod/qa/dev), so that benchmark data includes environment context.

#### Acceptance Criteria

1. WHEN running on hostname "usaz15ls082", THE script SHALL set environment to "prod"
2. WHEN running on hostname "usaz15ls080", THE script SHALL set environment to "qa"
3. WHEN running on hostname "usaz15ls081", THE script SHALL set environment to "dev"
4. WHEN `PIPELINE_ENV` environment variable is set, THE script SHALL use that value instead
5. WHEN environment cannot be determined, THE script SHALL default to "prod"

### Requirement 14: Pipeline Identification

**User Story:** As a data engineer, I want each pipeline run uniquely identified, so that I can track and query specific executions.

#### Acceptance Criteria

1. WHEN `--pipeline_name` parameter is provided, THE script SHALL use it as the pipeline identifier
2. WHEN `--pipeline_name` is not provided, THE script SHALL use the script basename as identifier
3. WHEN `--pipeline_type` parameter is provided, THE script SHALL store it (e.g., "batch", "streaming")
4. WHEN `--pipeline_type` is not provided, THE script SHALL default to "batch"
5. WHEN inserting to Oracle, THE script SHALL include pipeline_name, script_name, and pipeline_type

### Requirement 15: Logging and Monitoring

**User Story:** As a pipeline operator, I want detailed logging of Oracle operations, so that I can troubleshoot issues and monitor the feature.

#### Acceptance Criteria

1. WHEN default credentials are used, THE script SHALL log "Using default benchmark database credentials (user: refdb)"
2. WHEN Oracle DSN is not provided, THE script SHALL log "BENCHMARK_DB_DSN not provided, skipping Oracle benchmark insert"
3. WHEN credentials are missing, THE script SHALL log "BENCHMARK_DB_USER or BENCHMARK_DB_PASS not provided, skipping Oracle benchmark insert"
4. WHEN Oracle connection fails, THE script SHALL log "Failed to connect to Oracle benchmark DB: [error]"
5. WHEN Oracle insert succeeds, THE script SHALL log "Benchmark data inserted into Oracle pipeline_runs table"

### Requirement 16: JSON Serialization

**User Story:** As a data engineer, I want array and hash data serialized to JSON, so that complex data structures can be stored in CLOB columns.

#### Acceptance Criteria

1. WHEN serializing arrays, THE script SHALL use JSON::PP module with UTF-8 encoding
2. WHEN serializing metadata hash, THE script SHALL create valid JSON object
3. WHEN serializing benchmark hash, THE script SHALL include all statistics
4. WHEN serializing file arrays, THE script SHALL preserve array structure
5. WHEN JSON serialization fails, THE script SHALL log error and skip Oracle insert

### Requirement 17: Transaction Management

**User Story:** As a database administrator, I want proper transaction management, so that partial inserts are rolled back on failure.

#### Acceptance Criteria

1. WHEN Oracle connection is established, THE script SHALL disable AutoCommit
2. WHEN insert statement executes successfully, THE script SHALL commit the transaction
3. WHEN insert statement fails, THE script SHALL rollback the transaction
4. WHEN rollback completes, THE script SHALL log the failure and continue
5. WHEN connection is closed, THE script SHALL ensure no uncommitted transactions remain

### Requirement 18: Data Validation

**User Story:** As a data engineer, I want data validated before insertion, so that invalid data doesn't cause Oracle errors.

#### Acceptance Criteria

1. WHEN preparing timestamps, THE script SHALL convert ISO 8601 format to Oracle format
2. WHEN preparing numeric fields, THE script SHALL ensure they are valid numbers
3. WHEN preparing string fields, THE script SHALL handle null/empty values appropriately
4. WHEN preparing JSON fields, THE script SHALL validate JSON syntax
5. WHEN validation fails, THE script SHALL log error and skip Oracle insert

### Requirement 19: Performance Impact

**User Story:** As a pipeline operator, I want minimal performance impact from Oracle logging, so that pipeline execution time is not significantly increased.

#### Acceptance Criteria

1. WHEN Oracle insert is enabled, THE script SHALL complete within 5% of baseline execution time
2. WHEN Oracle connection fails, THE script SHALL timeout within 30 seconds
3. WHEN Oracle insert executes, THE script SHALL use prepared statements for efficiency
4. WHEN Oracle insert completes, THE script SHALL close connections promptly
5. WHEN measuring performance, THE script SHALL log elapsed time for Oracle operations

### Requirement 20: Security Best Practices

**User Story:** As a security engineer, I want credentials handled securely, so that sensitive information is not exposed.

#### Acceptance Criteria

1. WHEN logging credential information, THE script SHALL NOT log passwords
2. WHEN logging default credentials, THE script SHALL only log the username
3. WHEN using environment variables, THE script SHALL not expose them in logs
4. WHEN connection fails, THE script SHALL not include credentials in error messages
5. WHEN script exits, THE script SHALL not leave credentials in memory dumps

## Non-Functional Requirements

### Performance
- Oracle insert operation SHALL complete within 5 seconds under normal conditions
- Script SHALL handle up to 10,000 rows without performance degradation
- Database connection SHALL timeout after 30 seconds if unavailable

### Reliability
- Oracle failures SHALL NOT cause pipeline failures
- Script SHALL maintain 99.9% success rate for data processing
- Rollback mechanism SHALL ensure no partial data in database

### Maintainability
- Code SHALL follow existing Perl coding standards
- Subroutines SHALL be well-documented with comments
- Error messages SHALL be clear and actionable

### Security
- Credentials SHALL NOT appear in process listings
- Passwords SHALL NOT be logged
- Database connections SHALL use secure protocols

### Compatibility
- Script SHALL work with Oracle 11g and later
- Script SHALL work with Perl 5.10 and later
- Script SHALL work with DBI and DBD::Oracle modules

## Dependencies

- Perl DBI module
- Perl DBD::Oracle module
- Perl JSON::PP module
- Oracle database with pipeline_runs table
- Oracle client libraries (for DBD::Oracle)
- TNS configuration (for TNS name connections)

## Constraints

- Oracle insert is optional and non-blocking
- Default credentials are hardcoded in script
- Environment detection is hostname-based
- JSON serialization required for array/hash fields
- Timestamp format must match Oracle TO_TIMESTAMP format

## Success Criteria

1. Script successfully inserts benchmark data to Oracle when configured
2. Script continues execution when Oracle insert fails
3. Default credentials work without explicit configuration
4. Dual persistence mode works correctly
5. Existing pipelines work without modification
6. Documentation is complete and accurate
7. All acceptance criteria are met
8. Performance impact is within acceptable limits
