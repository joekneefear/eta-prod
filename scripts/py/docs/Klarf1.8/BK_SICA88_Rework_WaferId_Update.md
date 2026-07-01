# BK_SICA88_Rework WaferId Update

> **Last Updated:** 2026-03-17  
> **Scope:** `BK_SICA88_Rework` only

---

## Summary

`BK_SICA88_Rework` now uses a dedicated runtime `WaferRecord` resolver to build `WAFER_ID`.

This change was introduced to handle mixed incoming `WaferRecord` formats without knowing in advance what kind of BK Klarf rework file is being processed.

The resolver now decides at runtime based on the actual `WaferRecord` value.

---

## Business Rules Implemented

### 1. If `WaferRecord` is a scribe value

A scribe wafer value is identified using the YAML-configured regex:

```yaml
^([A-Z0-9]+)-(\d{2})\s[A-Z0-9]{2}$
```

Example:

- Input: `KG58Z02X-18 E7`
- Output: `KG58Z02X_18`

For scribe matches:

- `WaferId` is constructed directly from the scribe value
- This happens even if the on_lot RefDB endpoint returns no data, lot not found, or an error
- RefDB is not required for this scribe path

---

### 2. If `WaferRecord` is numeric

Examples:

- `4`
- `04`
- `18`

For numeric values:

- Wafer number is normalized to 2 digits using zero-padding
- `WaferId` is constructed as:

```text
<source lot>_<wafer number>
```

Example:

- RefDB `sourceLot`: `KG61Z2AX`
- `WaferRecord`: `4`
- Output: `KG61Z2AX_04`

---

## Source Lot Priority

For numeric wafer values, source lot resolution is:

1. **First choice:** on_lot RefDB metadata field `sourceLot`
2. **Fallback:** Klarf file `LotRecord`

When `LotRecord` is used for fallback:

- trailing `.S` is removed before constructing `WaferId`

Example:

- `LotRecord`: `KG61Z2AX.S`
- `WaferRecord`: `4`
- Output: `KG61Z2AX_04`

---

## No-Data / Error Behavior

When the selected site is `BK_SICA88_Rework`, the pipeline still keeps the existing SANDBOX routing behavior for missing RefDB metadata.

That means if the on_lot endpoint returns any of the following:

- `NO_DATA`
- `ERROR`
- `NULL`
- empty/missing status
- lot not found / unusable response

then:

- files are routed to SANDBOX when the selected mapping depends on `refdb` fields
- numeric `WaferId` construction falls back to `LotRecord`
- scribe `WaferId` construction still works directly from `WaferRecord`

So routing behavior and `WaferId` construction are now aligned with the business requirement.

---

## YAML Configuration Used

```yaml
BK_SICA88_Rework:
  env: "kri_klarf_18_epi_rework"
  fields:
    WaferId:
      type: wafer_record
      source: WaferRecord
      construction_mode: source_lot_wafer_number
      source_lot_refdb_source: sourceLot
      source_lot_source: LotRecord
      scribe_regex: "^([A-Z0-9]+)-(\\d{2})\\s[A-Z0-9]{2}$"
      scribe_wafer_group: 2
      scribe_replacement: "\\1_\\2"
      target: WAFER_ID
```

---

## Runtime Decision Flow

```text
Read WaferRecord
  ├─ If matches scribe regex
  │    └─ Build WaferId directly from scribe replacement
  │
  └─ Else if numeric
       ├─ Try RefDB sourceLot from on_lot
       ├─ If unavailable, use LotRecord from file
       └─ Build <sourceLot>_<zero-padded wafer number>
```

---

## Non-BK Sites

No specialized `wafer_record` logic is applied to the other sites in YAML.

Current state:

- `CZ2_KLARF_18_Si` keeps its original composite `WaferId`
- `DEFAULT` keeps its original direct `WaferId` mapping
- only `BK_SICA88_Rework` uses the new runtime resolver

---

## Code Areas Updated

- `scripts/py/lib/Enricher/Klarf18Enricher.py`
  - added `wafer_record` rule type
  - added source lot resolution helper
  - added wafer number extraction helper
  - added BK-specific construction mode handling

- `scripts/py/resources/Klarf18_Enrichment.yaml`
  - restricted specialized `WaferId` behavior to `BK_SICA88_Rework`
  - added YAML-configurable scribe regex/replacement/group settings

- `scripts/py/docs/Klarf1.8/claude.md`
  - updated main documentation to reflect current implementation

---

## Final Behavior Matrix

| WaferRecord Type | RefDB Status | Result |
|------------------|-------------|--------|
| Scribe match | Success | Build from scribe |
| Scribe match | No data / error | Build from scribe |
| Numeric | Success | Build from RefDB `sourceLot` + wafer number |
| Numeric | No data / error | Build from `LotRecord` + wafer number |
| Neither scribe nor numeric | Any | `NA` |
