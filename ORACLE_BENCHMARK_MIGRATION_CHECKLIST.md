# Oracle Benchmark Migration Checklist

Use this checklist to implement Oracle benchmark persistence for `getCamstarWafer2AssemblyGenealogy.pl`.

## Phase 1: Prerequisites

### Database Setup
- [ ] Identify target Oracle database (e.g., DWPRD, LOTGPRD)
- [ ] Verify database access and permissions
- [ ] Test connection: `sqlplus username/password@DSN`
- [ ] Verify TNS configuration: `tnsping DSN`

### Database Schema
- [ ] Review `pipeline-service-prod/sql/create_pipeline_runs.sql`
- [ ] Execute DDL to create `pipeline_runs` table
- [ ] Verify table creation: `SELECT COUNT(*) FROM pipeline_runs;`
- [ ] Review `pipeline-service-prod/sql/migration_add_metadata_benchmark.sql`
- [ ] Execute migration to add `metadata` and `benchmark` columns
- [ ] Verify columns exist: `DESC pipeline_runs;`

### Database User Setup
- [ ] Create dedicated database user for pipeline writes (recommended)
- [ ] Grant INSERT permission on `pipeline_runs` table
- [ ] Grant SELECT permission for testing/verification
- [ ] Test permissions with new user account

### Perl Environment
- [ ] Verify Perl installation: `perl -v`
- [ ] Check DBI module: `perl -MDBI -e 1`
- [ ] Check DBD::Oracle module: `perl -MDBD::Oracle -e 1`
- [ ] Install missing modules: `cpan DBI DBD::Oracle`
- [ ] Check JSON::PP module: `perl -MJSON::PP -e 1`
- [ ] Verify Oracle client libraries installed

## Phase 2: Configuration

### Credential Management
- [ ] Decide on credential storage method:
  - [ ] Environment variables (recommended)
  - [ ] Command-line arguments (testing only)
  - [ ] Oracle Wallet (production)
- [ ] Create secure password file if needed: `chmod 600 /secure/oracle_password.txt`
- [ ] Set environment variables in shell profile or systemd service
- [ ] Test credential access

### Script Configuration
- [ ] Review current pipeline invocation command
- [ ] Identify `--benchmark_log` parameter (if exists)
- [ ] Plan Oracle DSN value (TNS name or connection string)
- [ ] Plan `--pipeline_name` value (unique identifier)
- [ ] Plan `--pipeline_type` value (e.g., "batch")

## Phase 3: Testing (Development Environment)

### Syntax Validation
- [ ] Run syntax check: `perl -c scripts/getCamstarWafer2AssemblyGenealogy.pl`
- [ ] Review any syntax errors or warnings
- [ ] Run test script: `bash scripts/test_oracle_benchmark_syntax.sh`

### Connection Testing
- [ ] Test Oracle connection with credentials
- [ ] Verify INSERT permission on `pipeline_runs` table
- [ ] Test with minimal data insert

### Pilot Run - JSONL + Oracle (Dual Mode)
- [ ] Keep existing `--benchmark_log` parameter
- [ ] Add `--benchmark_db_dsn` parameter
- [ ] Set `BENCHMARK_DB_USER` environment variable
- [ ] Set `BENCHMARK_DB_PASS` environment variable
- [ ] Run pipeline with test data
- [ ] Verify JSONL file created successfully
- [ ] Verify record inserted into Oracle table
- [ ] Compare JSONL and Oracle data for consistency
- [ ] Review log file for any warnings

### Error Handling Testing
- [ ] Test with invalid credentials (should warn and continue)
- [ ] Test with invalid DSN (should warn and continue)
- [ ] Test with database unavailable (should warn and continue)
- [ ] Verify pipeline completes successfully in all cases
- [ ] Verify JSONL file still created when Oracle fails

### Data Validation
- [ ] Query inserted record: `SELECT * FROM pipeline_runs WHERE pipeline_name = 'test_pipeline';`
- [ ] Verify all timestamps are correct
- [ ] Verify row counts match expected values
- [ ] Verify file paths are correct
- [ ] Verify JSON columns contain valid JSON
- [ ] Check metadata JSON structure
- [ ] Check benchmark JSON structure

## Phase 4: QA Environment Testing

### QA Deployment
- [ ] Deploy updated script to QA environment
- [ ] Configure QA database credentials
- [ ] Update QA pipeline configurations
- [ ] Test with QA data sources

### Integration Testing
- [ ] Run full pipeline end-to-end
- [ ] Verify all output files generated
- [ ] Verify Oracle benchmark data inserted
- [ ] Test multiple concurrent pipeline runs
- [ ] Verify no database locking issues
- [ ] Test with various data volumes

### Performance Testing
- [ ] Measure overhead of Oracle insert
- [ ] Verify acceptable performance impact
- [ ] Test with large row counts
- [ ] Monitor database connection pool

## Phase 5: Production Rollout

### Pre-Production
- [ ] Review all test results
- [ ] Document any issues and resolutions
- [ ] Prepare rollback plan
- [ ] Schedule maintenance window if needed
- [ ] Notify stakeholders of changes

### Production Database Setup
- [ ] Create production database user
- [ ] Grant appropriate permissions
- [ ] Test production database connectivity
- [ ] Configure production credentials securely

### Gradual Rollout
- [ ] Deploy to one production pipeline first
- [ ] Monitor for 24-48 hours
- [ ] Review logs and database records
- [ ] Verify no issues or performance degradation
- [ ] Deploy to additional pipelines incrementally
- [ ] Monitor each deployment

### Monitoring Setup
- [ ] Create database monitoring queries
- [ ] Set up alerts for failed inserts (if desired)
- [ ] Create dashboard for pipeline metrics
- [ ] Document query examples for team

## Phase 6: Post-Deployment

### Validation
- [ ] Verify all pipelines writing to Oracle successfully
- [ ] Compare JSONL and Oracle data for consistency
- [ ] Review logs for any warnings or errors
- [ ] Verify no performance degradation

### Documentation
- [ ] Update team runbooks
- [ ] Document credential locations
- [ ] Document troubleshooting procedures
- [ ] Share query examples with team
- [ ] Update monitoring documentation

### Optimization (Optional)
- [ ] Consider removing `--benchmark_log` if Oracle is stable
- [ ] Optimize database indexes if needed
- [ ] Set up automated cleanup of old records
- [ ] Implement data retention policy

### Training
- [ ] Train team on new Oracle benchmark feature
- [ ] Share documentation with team
- [ ] Demonstrate query examples
- [ ] Review troubleshooting procedures

## Phase 7: Maintenance

### Regular Tasks
- [ ] Monitor database growth
- [ ] Review and optimize queries
- [ ] Archive old benchmark data
- [ ] Rotate database credentials
- [ ] Update documentation as needed

### Periodic Reviews
- [ ] Review pipeline performance trends
- [ ] Identify optimization opportunities
- [ ] Update monitoring and alerting
- [ ] Gather feedback from team

## Rollback Plan

If issues occur, rollback is simple:

1. **Remove Oracle parameters** from pipeline invocation:
   - Remove `--benchmark_db_dsn`
   - Remove `--benchmark_db_user` (if used)
   - Remove `--benchmark_db_pass` (if used)

2. **Keep JSONL logging**:
   - Ensure `--benchmark_log` parameter is present
   - Verify JSONL files are being created

3. **Script automatically falls back** to JSONL-only mode

4. **No code changes required** for rollback

## Success Criteria

- [ ] All pipelines successfully writing to Oracle
- [ ] No performance degradation
- [ ] No pipeline failures due to Oracle issues
- [ ] Data consistency between JSONL and Oracle
- [ ] Team trained and comfortable with new feature
- [ ] Monitoring and alerting in place
- [ ] Documentation complete and accessible

## Support Resources

- **Detailed Documentation**: `docs/oracle_benchmark_integration.md`
- **Quick Reference**: `scripts/ORACLE_BENCHMARK_QUICKSTART.txt`
- **Examples**: `scripts/getCamstarWafer2AssemblyGenealogy_oracle_benchmark_example.sh`
- **Schema**: `pipeline-service-prod/sql/create_pipeline_runs.sql`
- **Migration**: `pipeline-service-prod/sql/migration_add_metadata_benchmark.sql`

## Contact

For questions or issues during migration:
1. Review documentation in `docs/` directory
2. Check log files for specific error messages
3. Test database connectivity independently
4. Verify Perl module installation
5. Contact database team for Oracle-specific issues

---

**Migration Date**: _______________

**Completed By**: _______________

**Sign-off**: _______________
