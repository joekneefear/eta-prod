# PowerchipWatParser - Production-Ready Implementation

## 📁 Project Structure

```
scripts/py/
├── lib/
│   ├── Config/
│   │   └── PowerchipWatParsingConfig.py # ✨ NEW: Centralized configuration
│   ├── Parser/
│   │   └── PowerchipWatParser.py        # Main parser (legacy - refactor in progress)
│   └── Utility/
│       ├── PowerchipWatGapDetector.py   # ✨ NEW: Refactored gap detection logic
│       ├── PowerchipWatFileValidator.py # ✨ NEW: Pre-validation utilities
│       └── PowerchipWatQualityGate.py   # ✨ NEW: Quality assessment framework
└── tests/
    ├── __init__.py
    ├── test_powerchip_wat_parser.py # ✨ NEW: Comprehensive test suite
    └── requirements.txt             # Test dependencies
```

## 🚀 Quick Start

### Running Tests

```powershell
# Install test dependencies
cd C:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\scripts\py
pip install -r tests/requirements.txt

# Run all tests
pytest tests/test_powerchip_wat_parser.py -v

# Run specific test class
pytest tests/test_powerchip_wat_parser.py::TestGapDetector -v

# Run with coverage report
pytest tests/test_powerchip_wat_parser.py --cov=lib.Parser --cov-report=html
```

### Using the New Components

#### 1. Configuration Management

```python
from lib.Config.ParsingConfig import ParsingConfig

# Use default configuration
config = ParsingConfig()

# Override specific settings
config = ParsingConfig({
    'LEADING_GAP_THRESHOLD_LARGE': 10,
    'MIN_QUALITY_THRESHOLD': 0.7,
    'STRICT_MODE': True
})

# Create from legacy args
args = {'pad_token': 'NULL', 'site_sign_mode': 'signed'}
config = ParsingConfig.from_args(args)

# Validate configuration
config.validate()  # Raises ValueError if invalid
```

#### 2. Gap Detection (Refactored)

```python
from lib.Config.ParsingConfig import ParsingConfig
from lib.Utility.GapDetector import GapDetector

config = ParsingConfig()
detector = GapDetector(config)

# Parse row with gaps
row = "                                     -12.35458  0.7366  1.234"
result = detector.insert_nas_for_gaps(row, expected=11)

# Result: ["NA", "NA", "NA", "-12.35458", "0.7366", "1.234", ...]
```

#### 3. File Validation

```python
from lib.Utility.FileValidator import FileValidator

validator = FileValidator()

# Read file
with open('RGAAK2000.WAT', 'r') as f:
    lines = f.readlines()

# Validate structure
is_valid, errors, warnings = validator.validate_file_structure(lines)

if not is_valid:
    print("Validation failed:")
    for error in errors:
        print(f"  ERROR: {error}")

# Or use convenience method
validator.validate_and_report(lines, "RGAAK2000.WAT")
```

#### 4. Quality Gates

```python
from lib.Config.ParsingConfig import ParsingConfig
from lib.Utility.QualityGate import QualityGate

config = ParsingConfig({'MIN_QUALITY_THRESHOLD': 0.7})
quality_gate = QualityGate(config)

# Start quality report
quality_gate.start_report("RGAAK2000.WAT")

# Assess row quality
quality = quality_gate.assess_row_quality(
    row_number=10,
    wafer="06",
    site="-1",
    values=["NA", "-12.35458", "0.7366", ...],
    expected=11,
    method_used="heuristic"
)

# Check if acceptable
is_ok, error_msg = quality_gate.check_quality(quality, row_data)

# Finalize report
report = quality_gate.finalize_report()
print(report.summary())
```

## 🧪 Test Coverage

### Current Test Suite Coverage

- **Configuration Management**: 5 tests
- **Gap Detection**: 18 tests
  - Leading gap detection (large, medium, with/without deficit)
  - Middle gap detection
  - Trailing blank padding
  - Edge cases (empty row, single column, scientific notation)
- **File Validation**: 7 tests
  - Structure validation
  - Missing headers detection
  - Data row validation
- **Integration Tests**: 3 tests
  - Wafer 6 format (leading blanks)
  - Normal format
  - Mixed gaps format
- **Edge Cases**: 5 tests

**Total: 38 comprehensive tests**

### Running Specific Test Scenarios

```powershell
# Test leading gap detection (wafer 6 format)
pytest tests/test_powerchip_wat_parser.py::TestGapDetector::test_leading_gap_detection_large -v

# Test configuration validation
pytest tests/test_powerchip_wat_parser.py::TestParsingConfig::test_config_validation -v

# Test file validation
pytest tests/test_powerchip_wat_parser.py::TestFileValidator -v

# Test all edge cases
pytest tests/test_powerchip_wat_parser.py::TestEdgeCases -v
```

## 📊 Configuration Reference

### Gap Detection Thresholds

| Parameter | Default | Description |
|-----------|---------|-------------|
| `LEADING_GAP_THRESHOLD_LARGE` | 5 | Chars - always treated as leading gap |
| `LEADING_GAP_THRESHOLD_MEDIUM` | 3 | Chars - gap if token deficit exists |
| `GAP_MULTIPLIER_MEDIAN` | 1.8 | Multiplier for median gap calculation |
| `GAP_MULTIPLIER_TOKEN_WIDTH` | 1.5 | Multiplier for token width calculation |
| `GAP_THRESHOLD_MIN` | 3 | Chars - minimum gap threshold |

### Quality Gates

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MIN_QUALITY_THRESHOLD` | 0.5 | Minimum valid value ratio (0.0-1.0) |
| `STRICT_MODE` | False | Raise exceptions on quality failures |
| `MAX_QUALITY_WARNINGS` | 10 | Max warnings to log per file |

### Parsing Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `FIXED_WIDTH_ENABLED` | True | Use fixed-width column parsing |
| `FIXED_WIDTH_FIELD_SIZE` | 15 | Chars per fixed-width column |
| `PAD_TOKEN` | "NA" | Token for missing/empty values |
| `SITE_SIGN_MODE` | "stripped" | "signed" or "stripped" |

## 🔧 Integration Guide

### Step 1: Install Test Dependencies

```powershell
pip install pytest pytest-cov
```

### Step 2: Run Test Suite

```powershell
cd C:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\scripts\py
pytest tests/test_powerchip_wat_parser.py -v
```

Expected output:
```
tests/test_powerchip_wat_parser.py::TestParsingConfig::test_default_config PASSED
tests/test_powerchip_wat_parser.py::TestGapDetector::test_leading_gap_detection_large PASSED
...
========================== 38 passed in 2.45s ==========================
```

### Step 3: Validate Your WAT Files

```python
from lib.Parser.FileValidator import FileValidator

validator = FileValidator()
with open('your_file.WAT', 'r') as f:
    lines = f.readlines()

is_valid = validator.validate_and_report(lines, 'your_file.WAT')
```

### Step 4: Run Parser with Quality Gates

```python
from lib.Parser.ParsingConfig import ParsingConfig
from lib.Parser.QualityGate import QualityGate

# Configure with quality gates
config = ParsingConfig({
    'MIN_QUALITY_THRESHOLD': 0.8,  # 80% valid values required
    'STRICT_MODE': False  # Log warnings instead of raising errors
})

quality_gate = QualityGate(config)
quality_gate.start_report("RGAAK2000.WAT")

# ... parse file ...
# For each row, assess quality:
quality = quality_gate.assess_row_quality(...)

# Get final report
report = quality_gate.finalize_report()
print(report.summary())
```

## 📈 Performance Considerations

### Optimization Flags

```python
config = ParsingConfig({
    'ENABLE_EARLY_EXIT': True,  # Skip extra methods when confident
    'HIGH_CONFIDENCE_THRESHOLD': 1.0,  # 100% valid = early exit
    'LOG_METHOD_SELECTION': False,  # Reduce logging overhead
})
```

### Benchmarking

```powershell
# Run tests with timing
pytest tests/test_powerchip_wat_parser.py -v --durations=10
```

## 🐛 Debugging

### Enable Detailed Logging

```python
config = ParsingConfig({
    'LOG_METHOD_SELECTION': True,
    'MAX_LOG_ROWS': 50  # Log first 50 rows
})
```

### Inspect Quality Report

```python
report = quality_gate.finalize_report()

# Check pass rate
print(f"Pass rate: {report.pass_rate:.1%}")

# Review failed rows
for quality in report.low_quality_rows:
    print(quality.summary())

# Check warnings
for warning in report.warnings:
    print(f"Warning: {warning}")
```

## 📝 Best Practices

### 1. Always Validate Before Parsing

```python
validator = FileValidator()
is_valid, errors, warnings = validator.validate_file_structure(lines)
if not is_valid:
    raise ValueError(f"Invalid WAT file: {errors}")
```

### 2. Use Quality Gates for Production

```python
config = ParsingConfig({'MIN_QUALITY_THRESHOLD': 0.7, 'STRICT_MODE': True})
quality_gate = QualityGate(config)
# ... parsing with quality checks ...
```

### 3. Run Tests Before Deployment

```powershell
pytest tests/test_powerchip_wat_parser.py --cov=lib.Parser --cov-report=term-missing
```

### 4. Monitor Quality Reports

```python
report = quality_gate.finalize_report()
if report.pass_rate < 0.95:
    send_alert(f"Parse quality below 95%: {report.pass_rate:.1%}")
```

## 🚧 Migration from Legacy Parser

The new modular components are **backward compatible**. You can adopt them incrementally:

1. **Phase 1**: Add validation
   ```python
   validator = FileValidator()
   validator.validate_and_report(lines, filename)
   # Continue with existing parser
   ```

2. **Phase 2**: Add quality gates
   ```python
   quality_gate = QualityGate(config)
   # Wrap existing parsing with quality assessment
   ```

3. **Phase 3**: Refactor to use GapDetector
   ```python
   detector = GapDetector(config)
   result = detector.insert_nas_for_gaps(row, expected)
   ```

## 📚 Additional Resources

- **Test Suite**: [tests/test_powerchip_wat_parser.py](tests/test_powerchip_wat_parser.py)
- **Configuration**: [lib/Config/PowerchipWatParsingConfig.py](lib/Config/PowerchipWatParsingConfig.py)
- **Gap Detection**: [lib/Utility/PowerchipWatGapDetector.py](lib/Utility/PowerchipWatGapDetector.py)
- **Quality Gates**: [lib/Utility/PowerchipWatQualityGate.py](lib/Utility/PowerchipWatQualityGate.py)

## 🎯 Next Steps

1. ✅ Run test suite: `pytest tests/test_powerchip_wat_parser.py -v`
2. ✅ Validate your WAT files with `FileValidator`
3. ✅ Configure quality thresholds in `ParsingConfig`
4. ⏳ Integrate `GapDetector` into PowerchipWatParser (refactor in progress)
5. ⏳ Add quality gates to production pipeline

---

**Last Updated**: January 15, 2026  
**Version**: 2.1 (Modular Architecture)  
**Author**: junifferallan.garcia@onsemi.com
