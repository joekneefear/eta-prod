# Atomic Writing Audit (scripts/py)

**Date:** 2026-03-13  
**Requested scope:** check all first-party `.py` under `scripts/py` for atomic file writing / compression concerns only.  
**Explicitly excluded:** `scripts/py/virutal_env/**` and non-atomic-domain logic.

---

## Audit Method

- Searched first-party Python paths for write/move/compress operations.
- Reviewed direct write patterns (`open(..., 'w'/'a')`, `gzip.open(...,'w*')`, `json.dump`, `os.rename`, `os.replace`, `shutil.move/copy`).
- Classified each file as:
  - **Needs update (atomic domain)**
  - **Acceptable currently**
  - **Optional/low-priority atomic hardening**

---

## Needs Update (Atomic Domain)

### P0 / High Priority

1. `scripts/py/lib/Util.py`
   - `gzip_file()` writes directly to final `file.gz` then deletes source.
   - Risk: partially written `.gz` can be exposed on interruption.
   - Atomic-only remediation: write to `file.gz.tmp` in same dir, flush/fsync, `os.replace`, then remove source.

2. `scripts/py/apt2xml_ftx.py`
   - Uses `sed -i` (in-place mutation) and then non-atomic `Util.gzip_file()`.
   - Risk: published artifact mutated in place; non-atomic compression publish.
   - Atomic-only remediation: transform to temp file and `os.replace`; use atomic gzip helper.

3. `scripts/py/apt2xml_prb.py`
   - Same pattern/risk/remediation as `apt2xml_ftx.py`.

4. `scripts/py/lib/Parser/JndMetEdcParser.py`
   - `write_lots_to_file()` writes plain output directly, then gzip directly to final `.gz`, then deletes plain file.
   - Risk: partially published output on interruption in either phase.
   - Atomic-only remediation: plain write via temp+replace and gzip via temp+replace.

### P1 / Medium Priority

5. `scripts/py/lib/Writer.py`
   - Already stages temp files, but promotes with `os.rename` in multiple paths.
   - Risk: overwrite/portability edge behavior versus `os.replace` contract.
   - Atomic-only remediation: standardize promotions to `os.replace`; add flush/fsync before promote.

6. `scripts/py/lib/Formatter/SXML.py`
    - Duplicates temp/promote logic using `os.rename`.
    - Risk: drift from centralized atomic policy.
    - Atomic-only remediation: delegate to writer/shared atomic helper or switch to `os.replace` + fsync.

7. `scripts/py/lib/Formatter/IFF.py`
    - `save_dataframe_to_csv()` manually manages temp/promote path.
    - Risk: inconsistent atomic guarantees versus shared writer paths.
    - Atomic-only remediation: route through shared atomic helper/writer and use `os.replace`.

8. `scripts/py/pipelines/get_subcon_lot_metadata_lotG.py`
    - Uses temp files but promotes with `os.rename`.
    - Risk: overwrite behavior inconsistency.
    - Atomic-only remediation: use `os.replace` for final promote steps.

---

## Acceptable Currently (No Immediate Atomic Change Required)

1. `scripts/py/pipelines/get_dw_product_metadata_snowflake.py`
   - Uses temp staging and `os.replace` for final output and gzip publish.
   - Atomic posture is aligned with target pattern.

2. Most writer-based call sites that only call `Writer.open()/close()`
   - Inherit existing temp staging behavior.
   - Remaining hardening is centralized in `Writer.py` (already captured above).

---

## Deferred / Excluded For Now (By Request)

1. Direct gzip-final scripts:
   - `scripts/py/split_file_by_column.py`
   - `scripts/py/onhd_meyerberger_split_file_by_column.py`
   - `scripts/py/replace_null_with_na.py`

2. Monitor JSON writers:
   - `scripts/py/monitor/fcs_pp_monitor.py`
   - `scripts/py/monitor/pp_monit.py`
   - `scripts/py/monitor/pp_monit_not_async.py`
   - `scripts/py/monitor/pp_monit_final.py`
   - `scripts/py/monitor/stand_alone_monit.py`
   - `scripts/py/monitor/stand_alone_monit copy_enhanded.py`
   - `scripts/py/monitor/stand_alone_monit copy_orig.py`

3. Optional low-priority hardening items:
   - `scripts/py/get_snowflake_e142_extraction_manager.py`
   - `scripts/py/pipelines/get_snowflake_c142_extraction_manager.py`
   - `scripts/py/jnd_probe_upm_to_xml.py`
   - `scripts/py/klarf_defect_list_filter.py`

---

## Out-of-Scope / Not Flagged as Atomic Defect

1. Intentional append-only logs/stats (e.g., `open(...,'a')`) where append semantics are expected.
2. Lock-protected append flow in `scripts/py/lib/Utility/JndUtil.py` for accumulator CSV updates.
3. File moves that are operational staging/housekeeping, unless they publish a final externally consumed artifact.

---

## Recommended Remediation Order

1. `lib/Util.py::gzip_file` (unblocks multiple scripts)
2. `apt2xml_ftx.py`, `apt2xml_prb.py`
3. `JndMetEdcParser.py` atomic write + atomic gzip in `write_lots_to_file()`
4. centralized consistency hardening (`Writer.py`, `SXML.py`, `IFF.py`)
5. `get_subcon_lot_metadata_lotG.py` rename->replace standardization

---

## Final Items To Be Updated Now (Atomic Scope Only)

1. `scripts/py/lib/Util.py` (`gzip_file` atomic temp->replace)
2. `scripts/py/apt2xml_ftx.py` (remove in-place transform; use atomic output flow)
3. `scripts/py/apt2xml_prb.py` (remove in-place transform; use atomic output flow)
4. `scripts/py/lib/Parser/JndMetEdcParser.py` (`write_lots_to_file` atomic plain+gzip publish)
5. `scripts/py/lib/Writer.py` (`os.replace` standardization + flush/fsync before promote)
6. `scripts/py/lib/Formatter/SXML.py` (align with shared atomic promote contract)
7. `scripts/py/lib/Formatter/IFF.py` (`save_dataframe_to_csv` align with shared atomic contract)
8. `scripts/py/pipelines/get_subcon_lot_metadata_lotG.py` (`os.rename` -> `os.replace` in final promote paths)

---

## Summary

- The repository already has partial atomic patterns (temp staging) in core writer/pipeline areas.
- The biggest gaps are non-atomic gzip publication, in-place edits (`sed -i`), and direct JSON overwrite writes.
- No non-atomic-domain changes are proposed in this audit.
