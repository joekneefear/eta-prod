# Script Flow: n_getCamstarWafer2AssemblyGenealogy.pl

**Purpose**: Extract wafer→assembly genealogy and class-50 trace CSVs from Camstar, enriching with refdb/LOTG/DW lookups.

**Invocation / CLI**: script accepts options including `--SOURCE_DB`, `--SOURCE_WAREHOUSE`, `--SOURCE_SCHEMA`, `--START_HOURS`, `--END_HOURS`, `--OUT_GEN`, `--OUT_TRACE`, `--ARCHIVE_GEN`, `--ARCHIVE_TRACE`, `--LOGFILE`, `--BENCHMARK_LOG`, `--LOCK_FILE`, `--PIPELINE_NAME`, `--PIPELINE_TYPE`.

**High-level flow**:
1. Initialize
   - Parse CLI args and set defaults (`$startHours`, `$endHours`).
   - Initialize logging via `PDF::Log->init`.
   - Create and obtain exclusive file lock (prevent concurrent runs).
   - Validate `OUT_GEN`, `OUT_TRACE`, `ARCHIVE_*` dirs and create `tmp` subfolders.

2. Reference data
   - Load fab-code descriptions via `getFabCodes()` (Snowflake/Oracle query).

3. Build & execute Camstar query
   - Compose site-specific SQL via `getSQL($sourceDB)`.
   - Connect to Camstar (ODBC) using `odsConnect()` and execute the query.

4. Process result set (main loop)
   - For each row, normalize counts and wafer identifiers (`AssemblyQty`, `QtyConsumed`, `QtyRequired`, `ConsumeFactor`).
   - Resolve `assemblySourceLot`:
     - Use cache `%sourceLots` when available.
     - Call refdb `onlot/bylotid` web service (`getMetaFromRefDbWS`) for assembly lot.
     - Fallback to `lotGLookup()` when WS returns no_data or inconsistent results.
   - Resolve `fabSourceLot` and `fabID` for the material lot:
     - For Fairchild/fmr sites use `pplotprod` web service.
     - Use `onlot` WS for others; fallback to `lotGLookup()` when needed.
   - Normalize wafer IDs and scribe via `checkWaferID($sourceLot, $waferNum, $waferScribe, $fabID, $materialLotID)`.
   - Validate and possibly fix `assemblySourceLot` using `checkAssemblySourceLot()`.
   - Populate in-memory maps:
     - `%genInfo` keyed by `genEventName` (genealogy lines)
     - `%traceInfo` keyed by composite `assemblyLot:fabSourceLot:exensioWaferID:timestamp` (trace rows)

5. Output generation
   - Write a single genealogy file `Assembly2Wafer.$sourceDB.$date.a2wgen` (then gzip and move to archive + outgoing).
   - For each trace key in `%traceInfo`, create two CSVs:
     - `Assembly2Wafer.$sourceDB.$date.$assemblyLot.$dt.a2w.csv` (assembly-side)
     - `Wafer2Assembly.$sourceDB.$date.$fabSourceLot.$dt.w2a.csv` (wafer-side)
   - Each CSV includes the `class50Header` as first line.
   - Gzip each CSV, copy to archive, and move to outgoing folder.

6. Benchmarking & exit
   - If `--BENCHMARK_LOG` provided, call `writeBenchmark()` to append a JSONL record with run stats.
   - Release lock by process exit (`dpExit`).

**Key subroutines** (in-file)
- `getFabCodes()` — fetch fab code → description mapping from Snowflake/BIW.
- `getSQL($source)` — build the Camstar SQL query with site-specific logic.
- `odsConnect($dsn,$user,$pass)` — connect to ODBC DSN.
- `lotGLookup($lotid)` — query LOTG Oracle for source lot + fab fallback logic.
- `checkSourceLot($sourceLot,$fabID)` — normalize/truncate source lot by fab rules.
- `checkWaferID($sourceLot,$waferNum,$waferScribe,$fabID,$materialLotID)` — produce exensio wafer ID and adjust scribe (UMR lookup for UV5/EFK cases).
- `checkAssemblySourceLot($assemblyLot,$assemblySourceLot,$fabSourceLot,$fabID)` — reconcile assembly vs fab source lots.
- `writeBenchmark($path,$statsRef)` — normalize path and append JSONL benchmark entry.

**In-memory data structures**
- `%genInfo` — genealogy lines to write (one per event name).
- `%traceInfo` — trace CSV rows keyed per wafer event.
- `%sourceLots`, `%sourceFabs` — caches mapping material/assembly lots → source lot/fab.
- `%scribeIDs` — cache of scribe corrections found via UMR.

**Files produced**
- Genealogy: `$OUT_GEN/Assembly2Wafer.$SOURCE_DB.$DATE.a2wgen.gz` (archive copy in `$ARCHIVE_GEN`).
- Trace CSVs: `$OUT_TRACE/Wafer2Assembly...gz` and `Assembly2Wafer...gz` (archived in `$ARCHIVE_TRACE`).

**Errors & logging**
- Uses `PDF::Log` wrappers (`INFO`, `WARN`, `ERROR`) for messages.
- Prevents concurrent runs with a lock file; exits with `dpExit` on fatal errors.

**Where to look in code**
- main loop and row processing: near top-level while(fetchrow_hashref()) block.
- SQL composition: `getSQL()`.
- LOTG fallback + complex queries: `lotGLookup()`.

---
Generated from inspection of `scripts/n_getCamstarWafer2AssemblyGenealogy.pl` on 2026-02-13.
