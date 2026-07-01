# Metadata Quick Check Guide

## 30-Second Health Check

Run these commands to quickly diagnose metadata flow issues:

### 1. Check Oracle Database (10 seconds)
```sql
SELECT 
    COUNT(*) as total_records,
    COUNT(metadata) as records_with_metadata,
    MAX(start_utc) as latest_run
FROM pipeline_runs
WHERE pipeline_name LIKE '%E142%' OR pipeline_name LIKE '%Camstar%';
```

**Good**: `records_with_metadata` > 0 and `latest_run` is recent  
**Bad**: `records_with_metadata` = 0 → Perl scripts not writing metadata

### 2. Check API Endpoint (10 seconds)
```bash
curl -s "http://localhost:8080/pipeline-service/v1/get_pipeline_info?limit=1" | \
  python -m json.tool | grep -A 2 "file_type"
```

**Good**: Shows `"file_type_counts": {...}` and `"file_type_rows": {...}`  
**Bad**: Shows `"file_type_counts": null` → API not enriching data

### 3. Check Dashboard (10 seconds)
1. Open dashboard in browser
2. Press F12 (DevTools)
3. Go to Console tab
4. Paste and run:
```javascript
fetch('/api/pipelines?limit=1').then(r=>r.json()).then(d=>console.log(d.results[0]?.file_type_counts))
```

**Good**: Shows object like `{w2f: 1, a2w: 2}`  
**Bad**: Shows `undefined` → Dashboard not receiving data

---

## Common Issues & Quick Fixes

### Issue: "records_with_metadata = 0"
**Cause**: Perl scripts not running or failing  
**Fix**: 
```bash
# Check last run
ls -lt /path/to/logs/*.log | head -5

# Run script manually
perl scripts/getSnowflakeE142ModuleTrace.pl --args

# Check for Oracle errors in log
grep -i "oracle" /path/to/latest.log
```

### Issue: "API returns null for file_type_counts"
**Cause**: Pipeline service not configured for Oracle  
**Fix**:
```bash
# Check environment
echo $PIPELINE_BACKEND  # Should be "oracle"
echo $ORACLE_DSN        # Should be set
echo $ORACLE_USER       # Should be set

# Restart service with correct env
export PIPELINE_BACKEND=oracle
export ORACLE_DSN=your_dsn
export ORACLE_USER=your_user
export ORACLE_PASSWORD=your_password
python -m uvicorn main:main_app --reload
```

### Issue: "Dashboard shows no file type charts"
**Cause**: No E142/Camstar data in filtered results  
**Fix**:
1. Clear all filters in dashboard
2. Search for "E142" or "Camstar" in pipeline name filter
3. Check if `hasE142Data` computed property is true

---

## One-Line Diagnostics

### Check if metadata exists in Oracle
```sql
SELECT COUNT(*) FROM pipeline_runs WHERE metadata IS NOT NULL;
```

### Check if API is running
```bash
curl -s http://localhost:8080/pipeline-service/v1/health
```

### Check if dashboard can reach API
```bash
# From dashboard server
curl -s http://api-server:8080/pipeline-service/v1/health
```

### Check latest Perl script run
```bash
ls -lt /path/to/logs/*.log | head -1
```

### Check Oracle connection from Perl
```bash
perl -MDBI -e 'DBI->connect("dbi:Oracle:$ENV{ORACLE_DSN}", $ENV{ORACLE_USER}, $ENV{ORACLE_PASSWORD}) or die $DBI::errstr; print "OK\n"'
```

---

## Expected Data Flow Timeline

1. **T+0min**: Perl script starts, extracts data from Snowflake/Camstar
2. **T+20min**: Script finishes, writes metadata to Oracle
3. **T+20min**: API can immediately serve data with file_type_counts
4. **T+20min**: Dashboard refresh shows new file type statistics

If you don't see data after 30 minutes of script completion, something is wrong.

---

## Visual Indicators

### ✅ Everything Working
- Oracle: `records_with_metadata` > 0
- API: Returns `file_type_counts` object
- Dashboard: Shows "File Type Distribution" chart
- Dashboard: Shows "Trace File Statistics" panel with file counts

### ⚠️ Partial Working
- Oracle: Has metadata but old (> 24 hours)
- API: Returns data but no recent records
- Dashboard: Shows charts but with old data

### ❌ Not Working
- Oracle: `records_with_metadata` = 0
- API: Returns `file_type_counts: null`
- Dashboard: No file type charts visible
- Dashboard: `hasE142Data` = false

---

## Emergency Debug Mode

If nothing works, enable verbose logging:

### Perl Scripts
```perl
# Add to top of script
use Data::Dumper;
$Data::Dumper::Indent = 1;

# Before Oracle insert
print STDERR "Metadata JSON: " . Dumper(\%metadata) . "\n";
```

### Pipeline Service
```python
# In repository.py, line 320
print(f"DEBUG: metadata = {record_dict.get('metadata')}")
print(f"DEBUG: file_type_counts = {rec.file_type_counts}")
```

### Dashboard
```javascript
// In PipelineSummaryDashboard.vue, add to onMounted
console.log('Pipelines:', pipelines.value);
console.log('Has E142 data:', hasE142Data.value);
console.log('File type stats:', e142FileTypeStats.value);
```

---

## Success Criteria

You know metadata is working when:

1. ✅ Oracle query shows recent records with metadata
2. ✅ API returns file_type_counts in response
3. ✅ Dashboard shows "File Type Distribution" donut chart
4. ✅ Dashboard shows "Trace File Statistics" panel
5. ✅ File type counts match between Oracle, API, and Dashboard

---

## Contact Points for Each Layer

| Layer | File | Key Lines | What to Check |
|-------|------|-----------|---------------|
| Perl Write | `getSnowflakeE142ModuleTrace.pl` | 730-830 | Metadata JSON creation |
| Oracle Insert | `getSnowflakeE142ModuleTrace.pl` | 780-820 | bind_param(':metadata') |
| Oracle Read | `repository.py` | 305-324 | JSON parsing from CLOB |
| Enrichment | `utils.py` | 19-30 | extract_file_type_data() |
| API Response | `main.py` | 70-120 | PipelineInfo serialization |
| Dashboard Fetch | `pipelines.ts` (store) | - | API call |
| Dashboard Display | `PipelineSummaryDashboard.vue` | 310-340 | e142FileTypeStats computed |

---

## Quick Test: End-to-End

```bash
# 1. Run Perl script
perl scripts/getSnowflakeE142ModuleTrace.pl --test

# 2. Check Oracle (should see new record)
sqlplus user/pass@dsn <<EOF
SELECT date_code, DBMS_LOB.SUBSTR(metadata, 100, 1) 
FROM pipeline_runs 
ORDER BY start_utc DESC 
FETCH FIRST 1 ROW ONLY;
EOF

# 3. Check API (should return file_type_counts)
curl "http://localhost:8080/pipeline-service/v1/get_pipeline_info?limit=1" | \
  python -m json.tool | grep file_type_counts

# 4. Check Dashboard (should show in console)
# Open browser, F12, Console:
fetch('/api/pipelines?limit=1').then(r=>r.json()).then(d=>console.log(d.results[0]))
```

If all 4 steps show data, metadata flow is working correctly.
