# Atomic File Writing Final Implementation Plan (Approved Scope)

**Date:** 2026-03-13  
**Status:** Final implementation scope locked for current cycle.

---

## 1) Scope to Implement Now (Atomic Domain Only)

1. `scripts/py/lib/Util.py` (`gzip_file`)
2. `scripts/py/apt2xml_ftx.py`
3. `scripts/py/apt2xml_prb.py`
4. `scripts/py/lib/Parser/JndMetEdcParser.py` (`write_lots_to_file`)
5. `scripts/py/lib/Writer.py`
6. `scripts/py/lib/Formatter/SXML.py`
7. `scripts/py/lib/Formatter/IFF.py` (`save_dataframe_to_csv`)
8. `scripts/py/pipelines/get_subcon_lot_metadata_lotG.py`
9. `scripts/py/get_snowflake_e142_extraction_manager.py`
10. `scripts/py/pipelines/get_snowflake_c142_extraction_manager.py`
11. `scripts/py/jnd_probe_upm_to_xml.py`
12. `scripts/py/klarf_defect_list_filter.py`

**Atomic contract for all above files:**
- write temp in same target directory,
- flush + `os.fsync`,
- promote with `os.replace`,
- cleanup temp on failure,
- no in-place mutation of final artifacts.

---

## 2) Explicitly Deferred / Excluded For Now

Do **not** implement in this cycle:

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

---

## 3) File-by-File Final Implementation Actions

### 3.1 `scripts/py/lib/Util.py`
- Update `gzip_file()` to:
  - write gzip to `<final>.tmp`,
  - flush + fsync gzip stream/file descriptor,
  - `os.replace(tmp, final_gz)`,
  - remove source only after successful replace,
  - cleanup tmp in exception path.

### 3.2 `scripts/py/apt2xml_ftx.py`
- Remove in-place `sed -i` workflow.
- Apply XML entity normalization through atomic rewrite path (temp output + replace).
- Call updated atomic `Util.gzip_file()` only after transformed XML is safely published.

### 3.3 `scripts/py/apt2xml_prb.py`
- Apply same implementation model as `apt2xml_ftx.py`.

### 3.4 `scripts/py/lib/Parser/JndMetEdcParser.py`
- In `write_lots_to_file()`:
  - write plain XML-like output to temp then replace,
  - produce `.gz` via temp gzip then replace,
  - remove plain file after successful gzip publish when required by existing behavior.

### 3.5 `scripts/py/lib/Writer.py`
- Replace all final promote `os.rename` calls with `os.replace`.
- Ensure `close()` path flushes and fsyncs before promote.
- Ensure gzip/fork temp outputs are promoted with `os.replace`.
- Keep existing public behavior and filenames unchanged.

### 3.6 `scripts/py/lib/Formatter/SXML.py`
- Remove duplicated custom temp/rename behavior where possible.
- Align final promote operation with `Writer` atomic contract (`os.replace` + fsync-backed write path).

### 3.7 `scripts/py/lib/Formatter/IFF.py`
- In `save_dataframe_to_csv()`, align manual temp/promote logic to shared atomic contract.
- Use `os.replace` for final publish.

### 3.8 `scripts/py/pipelines/get_subcon_lot_metadata_lotG.py`
- Change final promote points from `os.rename` to `os.replace` where artifact publication occurs.
- Keep existing pipeline data/content behavior unchanged.

### 3.9 `scripts/py/get_snowflake_e142_extraction_manager.py`
- Apply atomic temp+replace for modfile/config artifact writes (`create_modfile`, `generate_crontab(output_file)`).
- Preserve current content format and command behavior.

### 3.10 `scripts/py/pipelines/get_snowflake_c142_extraction_manager.py`
- Apply atomic temp+replace for modfile/config artifact writes (`create_modfile`, `generate_crontab(output_file)`).
- Preserve current content format and command behavior.

### 3.11 `scripts/py/jnd_probe_upm_to_xml.py`
- When producing derived decompressed file, use temp write + replace to prevent partial plain output exposure.
- Keep downstream processing flow unchanged.

### 3.12 `scripts/py/klarf_defect_list_filter.py`
- In pass-through branch, publish output using atomic temp+replace (both copy/gzip output paths).
- Keep filtering and naming behavior unchanged.

---

## 4) Final Execution Order

1. `Util.py::gzip_file`
2. `apt2xml_ftx.py` and `apt2xml_prb.py`
3. `JndMetEdcParser.py`
4. `Writer.py`
5. `SXML.py` and `IFF.py`
6. `get_subcon_lot_metadata_lotG.py`
7. low-priority hardening: `get_snowflake_e142_extraction_manager.py`, `get_snowflake_c142_extraction_manager.py`, `jnd_probe_upm_to_xml.py`, `klarf_defect_list_filter.py`

---

## 5) Validation Checklist (Atomic Scope)

- [ ] No partial final artifact when failure is injected mid-write.
- [ ] Temp files are cleaned on exceptions.
- [ ] Existing output filenames/content format remain unchanged.
- [ ] Replace-overwrite behavior works for re-runs to same output path.
- [ ] No deferred/excluded files modified in this cycle.

---

## 6) Definition of Done

Implementation is complete when all 12 in-scope files above follow temp-write + fsync + `os.replace` publish semantics for final artifacts, with no in-place mutation of published outputs and no code changes outside atomic-writing scope.
