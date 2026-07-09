# Single-Phase Parsing: Aligned with DTS Approach

## Problem
Original two-phase approach was inefficient: parse → determine site → re-parse

## Solution
Implemented **single-phase parsing** aligned with DTS1k2k approach:

### New Flow (Optimal)
1. Load enrichment config
2. Decompress if needed
3. **Determine site** (CLI or DEFAULT)
4. **Load parser config** (using determined site)
5. **Parse XLSX once** with site-specific configuration ✓
6. Set lot in PPLogger
7. Set PPLogger env
8. Fetch RefDB
9. Enrich
10. Build limits and output

## Key Changes

**File:** `scripts/py/inno_ft_xlsx_sts8200_enricher.py`

### Step 3: Determine Site Early
```python
site = params.get('site') or "DEFAULT"
Log.INFO(f"Enrichment site: {site}")
```

### Step 4: Load Parser Config
```python
parser_config = InnoFtXlsxSts8200ParserConfig(
    config_file=parser_config_file, 
    site=site
)
```

### Step 5: Parse Once with Config
```python
parser = InnoFtXlsxSts8200Parser(config=parser_config, pplogger=pplogger)
model = parser.parse_to_model(working_file)
```

## Benefits

- ✓ **Single parse:** No re-parsing overhead
- ✓ **Efficient:** Config determines parsing from the start
- ✓ **Aligned with DTS:** Same architecture pattern
- ✓ **Site-aware:** Uses site-specific field mappings immediately
- ✓ **Flexible:** Works with explicit --site or DEFAULT fallback
- ✓ **No variable scope issues:** Site determined before use

## Comparison with DTS

| Aspect | DTS | INNO |
|--------|-----|------|
| Site source | CLI arg | CLI arg or DEFAULT |
| Config timing | Load before parse | Load before parse |
| Parse phases | 1 | 1 |
| Efficiency | Optimal | Optimal |

## Testing Instructions

```bash
python scripts/py/inno_ft_xlsx_sts8200_enricher.py \
  --infile 9UU190005.xlsx \
  --site=INNOBE \
  --ws_url=/path/to/url.yaml \
  --ws_source=prod \
  --out=/output/path \
  --logfile=/log/path \
  --pplog
```

Expected logs:
```
[INFO] Enrichment site: INNOBE
[INFO] Loaded parser configuration from: ...InnoFtXlsx_ParserConfig.yaml
[INFO] XLSX parsed successfully
```
