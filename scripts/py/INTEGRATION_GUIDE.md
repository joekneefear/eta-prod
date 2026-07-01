# Integration Guide - powerchip_pcm_wat_translator_enricher.py

## 🎯 Changes Made

The script has been updated to use the new modular parser components for improved robustness and quality monitoring.

---

## 📝 Updates Summary

### 1. **New Imports Added**
```python
from lib.Config.PowerchipWatParsingConfig import ParsingConfig
from lib.Utility.PowerchipWatFileValidator import FileValidator
from lib.Utility.PowerchipWatQualityGate import QualityGate
```

### 2. **Configuration Management**
The script now initializes parser configuration with quality thresholds:

```python
parser_config_overrides = {
    'MIN_QUALITY_THRESHOLD': 0.7,  # 70% valid values required
    'STRICT_MODE': False,  # Log warnings instead of raising errors
    'SUPPRESS_SUMMARY': params.get('suppress_summary', False)
}
parser_config = ParsingConfig(parser_config_overrides)
parser_config.validate()
```

**Benefits**:
- Configurable quality thresholds
- Validation of configuration values
- Easy tuning via command-line parameters

### 3. **File Pre-Validation**
Before parsing, the script now validates file structure:

```python
validator = FileValidator()
is_valid, errors, warnings = validator.validate_file_structure(file_lines)

if not is_valid:
    # Script exits with detailed error messages
    dp_exit(1, pplogger=pplogger, error="File validation failed")
```

**Benefits**:
- Early detection of malformed files
- Clear error messages
- Prevents wasted processing time

### 4. **Quality Gate Integration**
Real-time quality monitoring during parsing:

```python
quality_gate = QualityGate(parser_config)
quality_gate.start_report(os.path.basename(output))
# ... parsing happens ...
quality_report = quality_gate.finalize_report()
```

**Benefits**:
- Quality metrics for each parse
- Automatic detection of low-quality rows
- Comprehensive quality reports in logs

### 5. **Quality Report Logging**
Detailed quality metrics logged after parsing:

```
============================================================
Parsing Quality Report:
============================================================
  Total rows: 150
  Pass rate: 94.7%
  Failed rows: 8
  Warnings: 3
✓ Pass rate 94.7% meets quality standards
============================================================
```

### 6. **Quality Metrics Storage**
Quality data stored in model.misc for downstream use:

```python
model.misc['quality_report'] = {
    'total_rows': quality_report.total_rows,
    'pass_rate': quality_report.pass_rate,
    'failed_rows': quality_report.failed_rows,
    'warnings_count': len(quality_report.warnings)
}
```

---

## 🚀 Usage

### Standard Usage (No Changes Required)
The script works exactly as before:

```bash
python powerchip_pcm_wat_translator_enricher.py \
    --infile RGAAK2000.WAT \
    --out /output/path \
    --site YOUR_SITE \
    --ws_source prod
```

### New Optional Parameter
Suppress parsing summary if needed:

```bash
python powerchip_pcm_wat_translator_enricher.py \
    --infile RGAAK2000.WAT \
    --out /output/path \
    --site YOUR_SITE \
    --ws_source prod \
    --suppress_summary
```

---

## 📊 Log Output Changes

### Before
```
INFO: Input file=RGAAK2000.WAT
INFO: Outbox=/output/path
INFO: Site=YOUR_SITE
```

### After
```
INFO: Input file=RGAAK2000.WAT
INFO: Parser configuration initialized and validated
INFO: Outbox=/output/path
INFO: Site=YOUR_SITE
INFO: INPUT FILE=RGAAK2000.WAT
INFO: Validating WAT file structure...
INFO: ✓ File validation PASSED
INFO: Quality gate initialized for parsing assessment

...parsing happens...

INFO: ============================================================
INFO: Parsing Quality Report:
INFO: ============================================================
INFO:   Total rows: 150
INFO:   Pass rate: 94.7%
INFO:   Failed rows: 8
INFO:   Warnings: 3
INFO: ✓ Pass rate 94.7% meets quality standards
INFO: ============================================================
```

---

## 🔍 Error Handling

### File Validation Errors
If file structure is invalid:

```
ERROR: File validation FAILED:
ERROR:   - Missing LOT ID header line
ERROR:   - No valid data rows found
ERROR: File validation failed
```

**Result**: Script exits with error code 1

### Quality Warnings
If quality is below threshold but not critical:

```
WARN: ⚠ Pass rate 68.0% below recommended 90%
WARN: Low quality rows detected: 15
WARN:   - Row 10 (W06 S-1): 7/11 valid (63.6%), method=heuristic
WARN:   - Row 15 (W06 S-2): 6/11 valid (54.5%), method=heuristic
WARN:   - Row 20 (W06 S-3): 8/11 valid (72.7%), method=heuristic
WARN:   ... and 12 more low quality rows
```

**Result**: Script continues (STRICT_MODE=False), warnings logged

---

## 🎛️ Configuration Tuning

### Adjust Quality Threshold
Edit the script to change quality requirements:

```python
parser_config_overrides = {
    'MIN_QUALITY_THRESHOLD': 0.8,  # Increase to 80%
    'STRICT_MODE': True,  # Raise exceptions on failures
}
```

### Enable Strict Mode
For critical production environments:

```python
parser_config_overrides = {
    'MIN_QUALITY_THRESHOLD': 0.9,  # 90% required
    'STRICT_MODE': True,  # Fail on low quality
}
```

---

## 📈 Quality Monitoring

### Access Quality Metrics
Downstream processes can access quality data:

```python
if 'quality_report' in model.misc:
    metrics = model.misc['quality_report']
    if metrics['pass_rate'] < 0.95:
        send_alert(f"Low quality parse: {metrics['pass_rate']:.1%}")
```

### Trend Analysis
Log quality metrics to database for trending:

```python
quality_metrics = {
    'lot': model.header.LOT,
    'file': model.header.DATA_FILE_NAME,
    'total_rows': model.misc['quality_report']['total_rows'],
    'pass_rate': model.misc['quality_report']['pass_rate'],
    'timestamp': datetime.now()
}
# Store in database for trending
```

---

## ✅ Testing

### Test the Updated Script
1. **Basic test** (should work as before):
   ```bash
   python powerchip_pcm_wat_translator_enricher.py --infile test.WAT --out /tmp --site TEST --ws_source dev
   ```

2. **Test with invalid file** (should catch validation errors):
   ```bash
   echo "invalid content" > invalid.WAT
   python powerchip_pcm_wat_translator_enricher.py --infile invalid.WAT --out /tmp --site TEST --ws_source dev
   ```

3. **Check quality report in logs**:
   ```bash
   grep "Parsing Quality Report" your_log_file.log
   ```

---

## 🔧 Troubleshooting

### Issue: Import Errors
**Error**: `ModuleNotFoundError: No module named 'lib.Config.ParsingConfig'`

**Solution**: Ensure new modules are in correct location:
```
scripts/py/lib/
├── Config/
│   ├── __init__.py
│   └── ParsingConfig.py
└── Utility/
    ├── __init__.py
    ├── FileValidator.py
    ├── GapDetector.py
    └── QualityGate.py
```

### Issue: Validation Fails Unexpectedly
**Error**: `File validation FAILED: Missing parameter header line`

**Solution**: Check file structure. Required elements:
- LOT ID header
- WAF SITE parameter header
- At least 5 data rows

### Issue: Low Quality Reports
**Warning**: `Pass rate 65.0% below recommended 90%`

**Actions**:
1. Review low quality rows in log
2. Check for file formatting issues
3. Verify gap detection working correctly
4. Consider adjusting MIN_QUALITY_THRESHOLD if appropriate

---

## 📚 Related Documentation

- **[README_PARSER_IMPROVEMENTS.md](README_PARSER_IMPROVEMENTS.md)** - Complete usage guide for new components
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Technical summary of improvements
- **[integration_example.py](integration_example.py)** - Standalone example using new components
- **[tests/test_powerchip_wat_parser.py](tests/test_powerchip_wat_parser.py)** - Test suite (38 tests)

**Components**:
- **[lib/Config/ParsingConfig.py](lib/Config/ParsingConfig.py)** - Configuration management
- **[lib/Utility/GapDetector.py](lib/Utility/GapDetector.py)** - Gap detection logic
- **[lib/Utility/FileValidator.py](lib/Utility/FileValidator.py)** - File validation
- **[lib/Utility/QualityGate.py](lib/Utility/QualityGate.py)** - Quality assessment

---

## 🎯 Benefits Summary

| Feature | Before | After |
|---------|--------|-------|
| File Validation | ❌ None | ✅ Pre-validation with detailed errors |
| Quality Monitoring | ❌ None | ✅ Real-time quality assessment |
| Configuration | ⚠️ Hardcoded | ✅ Configurable thresholds |
| Error Messages | ⚠️ Generic | ✅ Specific and actionable |
| Quality Metrics | ❌ None | ✅ Stored in model.misc |
| Production Monitoring | ❌ None | ✅ Quality reports in logs |

---

## 🚦 Next Steps

1. ✅ **Deploy updated script** to test environment
2. ✅ **Monitor quality reports** in logs
3. ✅ **Tune thresholds** based on actual data
4. ⏳ **Set up quality monitoring** dashboard
5. ⏳ **Configure alerts** for low quality parses

---

**Last Updated**: January 15, 2026  
**Version**: 2.1 (Integrated with modular components)  
**Author**: junifferallan.garcia@onsemi.com
