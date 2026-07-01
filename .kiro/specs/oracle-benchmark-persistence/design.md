# Design Document: Oracle Benchmark Persistence

## Overview

This document describes the design and implementation of Oracle database persistence for benchmark data in the `getCamstarWafer2AssemblyGenealogy.pl` script. The feature adds the ability to write pipeline execution metrics to an Oracle database table while maintaining backward compatibility with existing JSONL-based logging.

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                  Pipeline Execution                          │
│  (getCamstarWafer2AssemblyGenealogy.pl)                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  Collect Benchmark    │
         │  Statistics           │
         │  - Timestamps         │
         │  - Row Counts         │
         │  - File Paths         │
         │  - Diagnostic Counters│
         └───────────┬───────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
         ▼                       ▼
┌────────────────┐      ┌────────────────┐
│ JSONL Writer   │      │ Oracle Writer  │
│ (Optional)     │      │ (Optional)     │
└────────────────┘      └────────────────┘
         │                       │
         ▼                       ▼
┌────────────────┐      ┌────────────────┐
│ benchmark.jsonl│      │ pipeline_runs  │
│ File           │      │ Table          │
└────────────────┘      └────────────────┘
```

### Component Design

#### 1. Command-Line Argument Parsing

**Module**: GetOptions configuration

**Purpose**: Parse new Oracle-related command-line arguments

**Implementation**:
```perl
GetOptions(
    \%hOptions,
    # ... existing options ...
    "BENCHMARK_LOG=s",
    "BENCHMARK_INCLUDE_NON_ARCHIVE!",
    "BENCHMARK_DB_DSN=s",
    "BENCHMARK_DB_USER:s",    # Optional string (can be empty)
    "BENCHMARK_DB_PASS:s",    # Optional string (can be empty)
    # ... other options ...
)
```

**Key Design Decisions**:
- Use `:s` (optional string) for user/pass to allow flag without value
- DSN uses `=s` (required string) since it must have a value if provided
- All Oracle parameters are optional to maintain backward compatibility

#### 2. Credential Resolution Logic

**Module**: `writeBenchmarkToOracle()` subroutine

**Purpose**: Resolve credentials from multiple sources with clear priority

**Implementation**:
```perl
sub writeBenchmarkToOracle() {
    my $optionsRef = shift;
    my $statsRef = shift;
    
    # Priority 1: Command-line explicit values
    my $user = $optionsRef->{BENCHMARK_DB_USER} || "";
    my $pass = $optionsRef->{BENCHMARK_DB_PASS} || "";
    
    # Priority 2: Environment variables (if command-line empty)
    $user = $ENV{BENCHMARK_DB_USER} if length($user) == 0;
    $pass = $ENV{BENCHMARK_DB_PASS} if length($pass) == 0;
    
    # Priority 3: Default credentials (if flag present but empty)
    if (exists($optionsRef->{BENCHMARK_DB_USER}) && length($user) == 0) {
        $user = "refdb";
        $pass = 'br#^gox66312sdAB';
        INFO("Using default benchmark database credentials (user: $user)");
    }
    
    # Validation
    return if !defined($dsn) || length($dsn) == 0;
    return if length($user) == 0 || length($pass) == 0;
    
    # ... continue with connection ...
}
```

**Key Design Decisions**:
- Check `exists()` to distinguish between "flag not passed" and "flag passed without value"
- Use `length()` to check for empty strings after environment variable fallback
- Log only when default credentials are actually used
- Return early if any required parameter is missing (non-blocking)

#### 3. Database Connection Management

**Module**: `writeBenchmarkToOracle()` subroutine

**Purpose**: Establish Oracle connection with proper error handling

**Implementation**:
```perl
my $dbh;
eval {
    $dbh = DBI->connect("dbi:Oracle:$dsn", $user, $pass, {
        PrintError => 0,    # Don't print errors to STDERR
        RaiseError => 1,    # Throw exceptions on errors
        AutoCommit => 0     # Manual transaction control
    });
};
if ($@ || !defined($dbh)) {
    WARN("Failed to connect to Oracle benchmark DB: $@");
    return;
}
```

**Key Design Decisions**:
- Use `eval` block to catch connection exceptions
- Disable AutoCommit for explicit transaction control
- Enable RaiseError for exception-based error handling
- Return on failure (non-blocking) rather than exit
- Log warning but don't expose credentials in error message

#### 4. Data Preparation and Serialization

**Module**: `writeBenchmarkToOracle()` subroutine

**Purpose**: Prepare data for Oracle insertion, including JSON serialization

**Implementation**:
```perl
# Prepare metadata JSON
my %metadata = (
    rows_fetched => $statsRef->{rows_fetched} || 0,
    rows_kept => $statsRef->{rows_kept} || 0,
    rows_skipped => $statsRef->{rows_skipped} || 0,
);

# Serialize arrays to JSON for CLOB columns
my $outputFilesGenJson = JSON::PP->new->utf8->encode($statsRef->{output_files_gen} || []);
my $outputFilesTraceJson = JSON::PP->new->utf8->encode($statsRef->{output_files_trace} || []);
my $archivedGenFilesJson = JSON::PP->new->utf8->encode($statsRef->{archived_gen_files} || []);
my $archivedTraceFilesJson = JSON::PP->new->utf8->encode($statsRef->{archived_trace_files} || []);
my $metadataJson = JSON::PP->new->utf8->encode(\%metadata);
my $benchmarkJson = JSON::PP->new->utf8->encode(\%benchmark);

# Convert ISO 8601 UTC timestamps to Oracle format
my $startUtcTs = $statsRef->{start_utc};
my $endUtcTs = $statsRef->{end_utc};
$startUtcTs =~ s/T/ /;
$startUtcTs =~ s/Z$//;
$endUtcTs =~ s/T/ /;
$endUtcTs =~ s/Z$//;
```

**Key Design Decisions**:
- Use JSON::PP for JSON serialization (core Perl module)
- Enable UTF-8 encoding for proper character handling
- Provide default empty arrays for missing data
- Convert ISO 8601 timestamps to Oracle-compatible format
- Separate metadata (diagnostic counters) from full benchmark data

#### 5. SQL Statement Preparation and Execution

**Module**: `writeBenchmarkToOracle()` subroutine

**Purpose**: Insert benchmark data using prepared statements

**Implementation**:
```perl
my $sql = q{
    INSERT INTO pipeline_runs (
        start_local, end_local, start_utc, end_utc,
        elapsed_seconds, elapsed_human, output_file, rowcount, log_file,
        pid, date_code, pipeline_name, script_name, pipeline_type, environment,
        archived_file, output_file_gen, output_files_gen, output_file_trace,
        output_files_trace, archived_gen_files, archived_trace_files,
        rows_extracted, rows_written, total_files, metadata, benchmark
    ) VALUES (
        TO_TIMESTAMP(:start_local, 'YYYY-MM-DD HH24:MI:SS'),
        TO_TIMESTAMP(:end_local, 'YYYY-MM-DD HH24:MI:SS'),
        TO_TIMESTAMP(:start_utc, 'YYYY-MM-DD HH24:MI:SS'),
        TO_TIMESTAMP(:end_utc, 'YYYY-MM-DD HH24:MI:SS'),
        :elapsed_seconds, :elapsed_human, :output_file, :rowcount, :log_file,
        :pid, :date_code, :pipeline_name, :script_name, :pipeline_type, :environment,
        :archived_file, :output_file_gen, :output_files_gen, :output_file_trace,
        :output_files_trace, :archived_gen_files, :archived_trace_files,
        :rows_extracted, :rows_written, :total_files, :metadata, :benchmark
    )
};

my $sth;
eval {
    $sth = $dbh->prepare($sql);
    $sth->bind_param(':start_local', $startLocalTs);
    $sth->bind_param(':end_local', $endLocalTs);
    # ... bind all parameters ...
    $sth->execute();
    $dbh->commit();
    INFO("Benchmark data inserted into Oracle pipeline_runs table");
};
if ($@) {
    WARN("Failed to insert benchmark data to Oracle: $@");
    eval { $dbh->rollback(); };
}
```

**Key Design Decisions**:
- Use prepared statements with bind parameters for security and performance
- Use Oracle TO_TIMESTAMP function for timestamp conversion
- Wrap execution in eval block for exception handling
- Commit explicitly on success
- Rollback on failure (within eval to catch rollback errors)
- Log success/failure appropriately

#### 6. Dual Persistence Orchestration

**Module**: Main script execution flow

**Purpose**: Coordinate writing to both JSONL and Oracle

**Implementation**:
```perl
# Collect statistics
my %stats = (
    start_local => $startLocal,
    end_local => $endLocal,
    # ... all statistics ...
);

# Write to JSONL file (if configured)
if (defined($hOptions{BENCHMARK_LOG}) && length($hOptions{BENCHMARK_LOG}) > 0) {
    writeBenchmark($hOptions{BENCHMARK_LOG}, \%stats);
}

# Write to Oracle DB (if configured)
if (defined($hOptions{BENCHMARK_DB_DSN}) && length($hOptions{BENCHMARK_DB_DSN}) > 0) {
    writeBenchmarkToOracle(\%hOptions, \%stats);
}
```

**Key Design Decisions**:
- Write to JSONL first (faster, more reliable)
- Write to Oracle second (may fail, non-blocking)
- Both operations are independent
- Both operations are optional
- Failures in one don't affect the other

## Database Schema

### pipeline_runs Table Structure

```sql
CREATE TABLE pipeline_runs (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    start_local TIMESTAMP,
    end_local TIMESTAMP,
    start_utc TIMESTAMP,
    end_utc TIMESTAMP,
    elapsed_seconds NUMBER,
    elapsed_human VARCHAR2(100),
    output_file VARCHAR2(500),
    rowcount NUMBER,
    log_file VARCHAR2(500),
    pid NUMBER,
    date_code VARCHAR2(50),
    pipeline_name VARCHAR2(200),
    script_name VARCHAR2(200),
    pipeline_type VARCHAR2(50),
    environment VARCHAR2(20),
    archived_file VARCHAR2(500),
    output_file_gen VARCHAR2(500),
    output_files_gen CLOB,
    output_file_trace VARCHAR2(500),
    output_files_trace CLOB,
    archived_gen_files CLOB,
    archived_trace_files CLOB,
    rows_extracted NUMBER,
    rows_written NUMBER,
    total_files NUMBER,
    metadata CLOB,
    benchmark CLOB,
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);
```

**Key Design Decisions**:
- Use IDENTITY column for auto-incrementing primary key
- Use TIMESTAMP for all time-related fields
- Use CLOB for JSON arrays and objects
- Use VARCHAR2 for file paths (500 chars sufficient)
- Add created_at for audit trail
- Include both summary fields (rowcount) and detailed JSON (benchmark)

### JSON Column Structures

#### metadata CLOB
```json
{
    "rows_fetched": 1234,
    "rows_kept": 1200,
    "rows_skipped": 34
}
```

#### benchmark CLOB
```json
{
    "start_local": "2026-03-02 10:30:00",
    "end_local": "2026-03-02 10:45:30",
    "start_utc": "2026-03-02T18:30:00Z",
    "end_utc": "2026-03-02T18:45:30Z",
    "elapsed_seconds": 930,
    "elapsed_human": "15m 30s",
    "output_file": "Assembly2Wafer.CEBU.20260302_103000.a2wgen.gz",
    "rowcount": 1200,
    "rows_fetched": 1234,
    "rows_kept": 1200,
    "rows_skipped": 34,
    "rows_extracted": 1234,
    "rows_written": 1200,
    "total_files": 5,
    "output_files_gen": ["file1.gz"],
    "output_files_trace": ["file2.gz", "file3.gz"],
    "archived_gen_files": ["archive1.gz"],
    "archived_trace_files": ["archive2.gz", "archive3.gz"],
    "log_file": "./log/getCamstarWafer2AssemblyGenealogy.log",
    "pid": 12345,
    "date_code": "20260302_103000",
    "pipeline_name": "camstar_wafer2assembly_cebu",
    "script_name": "getCamstarWafer2AssemblyGenealogy.pl",
    "pipeline_type": "batch",
    "environment": "prod"
}
```

## Error Handling Strategy

### Error Categories and Responses

| Error Type | Detection | Response | Impact |
|------------|-----------|----------|--------|
| Missing DSN | Check if parameter provided | Skip Oracle insert, log info | None - JSONL continues |
| Missing credentials | Check user/pass length | Skip Oracle insert, log warning | None - JSONL continues |
| Connection failure | DBI->connect exception | Log warning, return | None - pipeline continues |
| SQL prepare failure | prepare() exception | Log warning, rollback, return | None - pipeline continues |
| SQL execute failure | execute() exception | Log warning, rollback, return | None - pipeline continues |
| JSON serialization failure | encode() exception | Log warning, return | None - pipeline continues |
| Timestamp conversion failure | Regex/format error | Log warning, return | None - pipeline continues |

### Non-Blocking Design Principles

1. **All Oracle operations wrapped in eval blocks**
   - Exceptions caught and logged
   - Execution continues after logging

2. **Early returns on validation failures**
   - Check DSN, credentials before attempting connection
   - Return immediately if prerequisites not met

3. **Transaction rollback on failure**
   - Rollback wrapped in eval (rollback itself may fail)
   - Ensures no partial data in database

4. **Pipeline always exits with success**
   - Oracle failures don't change exit code
   - Data processing success is independent of logging

## Performance Considerations

### Optimization Strategies

1. **Prepared Statements**
   - Use bind parameters instead of string interpolation
   - Reduces SQL parsing overhead
   - Improves security (SQL injection prevention)

2. **Single Connection**
   - Open connection once per execution
   - Close after insert completes
   - Avoid connection pool overhead for single insert

3. **Minimal Data Transformation**
   - JSON serialization only for arrays/hashes
   - Simple string operations for timestamps
   - No unnecessary data copying

4. **Asynchronous Potential** (Future Enhancement)
   - Could fork process for Oracle insert
   - Main pipeline continues immediately
   - Child process handles Oracle operation

### Performance Metrics

Expected overhead:
- Connection establishment: 100-500ms
- Data preparation: 10-50ms
- SQL execution: 50-200ms
- Total overhead: 160-750ms (typically <1% of pipeline runtime)

## Security Considerations

### Credential Protection

1. **No passwords in logs**
   - Only log usernames
   - Never log password values
   - Sanitize error messages

2. **Environment variable support**
   - Preferred method for custom credentials
   - Not visible in process listings
   - Can be sourced from secure files

3. **Default credentials**
   - Hardcoded in script (acceptable for shared service account)
   - Only used when explicitly requested via flag
   - Logged when used for transparency

### Database Security

1. **Least privilege principle**
   - Database user only needs INSERT on pipeline_runs
   - No SELECT, UPDATE, DELETE required
   - No DDL permissions required

2. **Connection security**
   - Use Oracle Wallet in production (future enhancement)
   - Support for encrypted connections
   - TNS configuration controls connection security

## Testing Strategy

### Unit Testing

1. **Credential Resolution**
   - Test command-line explicit values
   - Test environment variable fallback
   - Test default credential activation
   - Test missing credential handling

2. **Data Preparation**
   - Test JSON serialization
   - Test timestamp conversion
   - Test null/empty value handling
   - Test array serialization

3. **Error Handling**
   - Test connection failures
   - Test SQL execution failures
   - Test rollback behavior
   - Test non-blocking behavior

### Integration Testing

1. **Database Operations**
   - Test successful insert
   - Test transaction commit
   - Test transaction rollback
   - Test connection timeout

2. **Dual Persistence**
   - Test JSONL + Oracle
   - Test JSONL only
   - Test Oracle only
   - Test both failures

3. **End-to-End**
   - Test full pipeline with Oracle enabled
   - Test performance impact
   - Test concurrent executions
   - Test various data volumes

## Migration Strategy

### Phase 1: Development Testing
- Deploy to dev environment
- Test with default credentials
- Validate data in database
- Compare JSONL and Oracle data

### Phase 2: QA Validation
- Deploy to QA environment
- Run parallel with JSONL
- Monitor for errors
- Validate performance

### Phase 3: Production Rollout
- Deploy to one production pipeline
- Monitor for 24-48 hours
- Gradually roll out to additional pipelines
- Keep JSONL as backup during transition

### Phase 4: Optimization
- Consider removing JSONL if Oracle stable
- Implement monitoring and alerting
- Optimize queries for reporting
- Implement data retention policy

## Rollback Plan

### Immediate Rollback
1. Remove `--benchmark_db_dsn` from pipeline invocation
2. Keep `--benchmark_log` parameter
3. Script automatically reverts to JSONL-only mode
4. No code changes required

### Gradual Rollback
1. Remove Oracle parameters from one pipeline at a time
2. Monitor for issues
3. Keep Oracle parameters on stable pipelines
4. Document any issues encountered

## Future Enhancements

### Potential Improvements

1. **Asynchronous Insertion**
   - Fork child process for Oracle insert
   - Main pipeline continues immediately
   - Further reduces performance impact

2. **Batch Insertion**
   - Accumulate multiple runs
   - Insert in batches
   - Reduces connection overhead

3. **Oracle Wallet Support**
   - Eliminate password management
   - Improve security
   - Simplify credential rotation

4. **Retry Logic**
   - Retry failed inserts
   - Exponential backoff
   - Queue for later insertion

5. **Monitoring Integration**
   - Prometheus metrics
   - Grafana dashboards
   - Alerting on failures

6. **Data Retention**
   - Automated archival of old records
   - Partitioning by date
   - Compression for archived data

## Dependencies

### Required Perl Modules
- DBI (database interface)
- DBD::Oracle (Oracle driver)
- JSON::PP (JSON serialization)

### Required Infrastructure
- Oracle database (11g or later)
- Oracle client libraries
- TNS configuration (for TNS names)
- pipeline_runs table created

### Optional Components
- Oracle Wallet (for credential management)
- Monitoring system (for alerting)
- Backup system (for data retention)

## Documentation

### User Documentation
- `docs/oracle_benchmark_integration.md` - Comprehensive guide
- `scripts/ORACLE_BENCHMARK_QUICKSTART.txt` - Quick reference
- `DEFAULT_CREDENTIALS_USAGE.md` - Default credentials guide
- `CREDENTIAL_FLOW_DIAGRAM.txt` - Visual credential flow

### Developer Documentation
- `ORACLE_BENCHMARK_CHANGES.md` - Implementation summary
- `ORACLE_BENCHMARK_MIGRATION_CHECKLIST.md` - Migration guide
- This design document

### Operational Documentation
- Example shell scripts with usage patterns
- Query examples for reporting
- Troubleshooting guide
- Monitoring setup guide

## Conclusion

This design provides a robust, non-blocking Oracle persistence layer for benchmark data while maintaining full backward compatibility. The implementation follows best practices for error handling, security, and performance, ensuring that the feature can be adopted gradually with minimal risk.
