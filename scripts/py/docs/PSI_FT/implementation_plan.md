# MeasuringEquipment — Filename-Based Tool Extraction

## Goal

Add `MeasuringEquipment` (tool/handler ID) extraction from the input filename for the PSI pipeline. The tool name follows the pattern `TH###` or `TH-###` (e.g., `TH193`, `TH-193`), and should be normalized to `TH-###` format.

**Regex:** `(?<=_)(TH\d{3}|TH-\d{3})`

**Examples:**

| Filename | Extracted | Normalized |
|----------|-----------|------------|
| `RG_FT_UJ4C075060K4S-D1_S7U050039_51000C7N_TH193_.CSV` | `TH193` | `TH-193` |
| `FT_UJ4C075060K4S-D1_S7U050039_51000C7N_TH193_DTA.CSV` | `TH193` | `TH-193` |
| `QA_UJ4C075060K4S-D1_S7U050039_51000C7N_TH193_DTA.CSV` | `TH193` | `TH-193` |
| (no match) | — | `-` |

## Proposed Changes

### Parser — QorvoPsiParser

#### [MODIFY] [QorvoPsiParser.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/QorvoPsiParser.py)

Add a shared static/class method `extract_measuring_equipment(filename)`:

```python
@staticmethod
def extract_measuring_equipment(filename):
    """Extract tool name (TH### or TH-###) from filename and normalize to TH-### format."""
    basename = os.path.basename(filename)
    match = re.search(r'(?<=_)(TH-?\d{3})', basename, re.IGNORECASE)
    if match:
        tool = match.group(1).upper()
        if not tool.startswith("TH-"):
            tool = f"TH-{tool[2:]}"
        return tool
    return "-"
```

Then set it in existing parse methods:

- **`parse_to_model()`** — after building `header_data` dict (~line 314), add:
  ```python
  header_data['MEASURING_EQUIPMENT'] = self.extract_measuring_equipment(infile)
  ```

- **`parse_to_model_RG()`** — after building `header_data` dict (~line 763), add:
  ```python
  header_data['MEASURING_EQUIPMENT'] = self.extract_measuring_equipment(infile)
  ```

> **Why here?** The `infile` parameter (the original filename) is already available in both methods and contains the tool ID. This keeps extraction inside the parser where all other header fields are set — consistent with existing patterns.

---

### Parser — QorvoPsiCrParser

#### [MODIFY] [QorvoPsiCrParser.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/lib/Parser/QorvoPsiCrParser.py)

Currently (line 163), `MEASURING_EQUIPMENT` is derived from the `Comment` row:
```python
header.MEASURING_EQUIPMENT = matches["Comment"].group(1).strip().split(" ")[-1]
```

**Two options — need your input:**

1. **Option A — Filename takes priority over Comment:** Add the same `extract_measuring_equipment()` method and use it as a fallback/override if the `Comment` field doesn't yield a valid tool ID, or always prefer the filename.

2. **Option B — Keep Comment as primary, filename as fallback:** Only use filename extraction if `Comment` doesn't produce a result (i.e., `MEASURING_EQUIPMENT` is empty/`-`/`NA` after header extraction).

> [!IMPORTANT]
> Which approach do you prefer for `QorvoPsiCrParser`? The Comment-based extraction is already in place. Should the filename regex **override** it, or act as a **fallback**?

---

### No Changes Needed

- **`qorvo_ft_psi_csv.py`** — No changes. The filename is already passed as `infile` to the parser.
- **`qorvo_ft_psi_cr_csv.py`** — No changes. The filename is already passed as `infile` to the parser constructor.
- **`Metadata.py`** — `MEASURING_EQUIPMENT` is already declared in the attribute list (line 52).
- **`Writer.py` / `IFF.py`** — `MEASURING_EQUIPMENT` flows through `Model.header` → `IFF.header_to_string()` automatically since it iterates over `metadata.list()`.

## Verification Plan

### Manual Verification

1. **Dry-run test with a sample filename:** Create a small scratch script that imports `QorvoPsiParser` and calls `extract_measuring_equipment()` with known filenames from the spec:
   ```
   python -c "from lib.Parser.QorvoPsiParser import QorvoPsiParser; print(QorvoPsiParser.extract_measuring_equipment('RG_FT_UJ4C075060K4S-D1_S7U050039_51000C7N_TH193_.CSV'))"
   ```
   Expected: `TH-193`

2. **No-match test:**
   ```
   python -c "from lib.Parser.QorvoPsiParser import QorvoPsiParser; print(QorvoPsiParser.extract_measuring_equipment('FT_DEVICE_LOTID.DTA'))"
   ```
   Expected: `-`

3. **End-to-end:** If you have a sample PSI CSV file available, run the full script and verify the output IFF contains `MEASURING_EQUIPMENT=TH-193` in the `<HEADER>` section. Please let me know if there is a sample file path available or if this needs to be manually validated on the server.
