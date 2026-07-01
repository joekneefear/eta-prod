## XML Malformed — Knowledge Base

Purpose
-------
This document captures the root cause, fixes, and recommendations for handling malformed XML files observed in the codebase (escaped control characters, invalid UTF-8 sequences and other characters not allowed by XML 1.0).

Root cause summary
------------------
- Many malformed files contain invalid control characters (e.g. ESC 0x1B), null bytes, or broken/incomplete UTF-8 sequences.
- These produce XML parse errors such as "not well-formed (invalid token)" and fail early in the pipeline.

Files affected
--------------
- scripts/py/lib/Parser/SxmlParser.py
  - Status: FIX APPLIED
  - What was done: Added encoding-cleanup (replace/strip invalid UTF-8), removal of replacement character, strict XML 1.0 character filtering, ampersand/angle-bracket escaping for attributes, whitespace normalization, null-byte removal, final UTF-8 validation, diagnostics and a regex fallback to create a minimal tree when full parsing fails.
  - Assessment: Best practical solution implemented in parser — sanitizes aggressively while preserving as much data as possible and falls back safely when parsing still fails.

- scripts/py/lib/Enricher/SxmlEnricher.py
  - Status: FIX APPLIED
  - What was done: Enricher preserves original SXML formatting, performs line-by-line enrichment, and contains graceful error handling and a fallback to return original content with metadata if enrichment fails.
  - Assessment: Good approach — keeps format fidelity and avoids further corrupting malformed inputs.

- scripts/py/jnd_probe_tesec_wmc_enricher.py
  - Status: INTEGRATED
  - What was done: Instantiates `SxmlParser` with sanitizer config, checks `is_malformed`, logs when sanitization occurred, and purposely does not auto-route to SANDBOX (explicit design choice documented in the script).
  - Assessment: Behavior is intentional. If policy requires automatic sandboxing of sanitized files for this pipeline, toggle writer routing or set `writer_instance.noMeta = True` when `is_malformed` is True. Otherwise current implementation is acceptable.

- scripts/py/lib/Util.py
  - Status: FIX APPLIED (compression/atomic write)
  - What was done: `Util.gzip_file` writes to a same-dir temporary file, fsyncs, then `os.replace()` to atomically create `.gz`, and deletes original; `is_gzipped` guard avoids double compression.
  - Assessment: Atomic compression is implemented correctly.

- scripts/py/apt2xml_ftx.py and scripts/py/apt2xml_prb.py
  - Status: PARTIAL
  - What was done: Both scripts call `normalize_xml_entities_atomic()` which writes a temp file, fsyncs and `os.replace()` the normalized XML — atomic swap is implemented. They then call `Util.gzip_file` which is atomic as noted above.
  - Caveat: The Java conversion step (`cfg_java -jar cfg_apt2xml ... output_file`) writes `output_file` directly before Python normalization. That Java step is outside the Python atomic-write wrapper; if the Java tool can be directed to write to a temp path or stdout, the pipeline can be fully atomic end-to-end.

- docs/FINAL_SOLUTION_SUMMARY.md
  - Status: DOCUMENTATION
  - What was done: Detailed write-up covering diagnostics, sanitization approach, test cases and results.
  - Assessment: Useful reference; keep in sync with implementation notes below.

Was the best solution applied?
-----------------------------
- Parser-level sanitization (in `SxmlParser.py`) is the correct place to do aggressive clean-up: it centralizes fixes, provides diagnostics, and prevents downstream components from needing to reimplement the same logic. The implemented sanitizer follows best-practice order: fix encoding → remove invalid XML chars → escape problematic markup → final validation. This is the recommended solution for this class of problems.
- Enricher-level behavior is correct: preserve original formatting and avoid changing structure that the format readers depend upon.
- Compression and atomic writes in `Util.gzip_file` and `normalize_xml_entities_atomic` are implemented correctly and follow atomic-swap best practices.

Remaining gaps / recommendations
--------------------------------
1. Java converter atomicity (optional): If you need the entire end-to-end pipeline to be atomic (no partially-written `.xml` ever visible), consider changing the Java converter invocation to write to a temp filename in the same directory and then let Python rename it into place. This is optional since normalization + gzip are already atomic, but it eliminates a short window where `output_file` may be incomplete.

2. Configuration & monitoring:
   - Ensure sanitizer options are configurable via YAML for site-specific rules (some sites may want different removal/escape policies).
   - Add logging counters/metrics for how often files required sanitization; route frequent offenders for upstream remediation.

3. Tests:
   - Add unit tests for the sanitizer covering: ESC sequences, null bytes, broken UTF-8, unescaped `&`, `<` in attribute values, and large files.
   - Add an integration test that simulates the Java conversion + normalization + gzip pipeline.

4. Policy decision: SANDBOX routing
   - Some scripts (e.g. `jnd_probe_tesec_wmc_enricher.py`) intentionally do not auto-route sanitized files to SANDBOX. If organizational policy mandates sandboxing for any file that was sanitized, change the writer instantiation to set `noMeta=True` when `parser.is_malformed` is True.

How to use this doc
-------------------
- This is the canonical knowledge artifact for malformed-XML work. Link to it from `FINAL_SOLUTION_SUMMARY.md` and place a short cross-reference comment in `SxmlParser.py` and `SxmlEnricher.py` header blocks.

Contact / authors
-----------------
- Original work and fixes by `junifferallan.garcia@onsemi.com`

Revision history
----------------
- 2026-03-17 - Initial knowledge file created.
