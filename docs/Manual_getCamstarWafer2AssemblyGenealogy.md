# Manual Extraction Guide: getCamstarWafer2AssemblyGenealogy.pl

This guide explains how to manually trigger the Camstar wafer consumption genealogy extraction. This script queries various Camstar databases (MDS) to resolve wafer-to-assembly relationships.

## Core Command Structure

To run the script directly, you should use the `perl_db` interpreter.

```bash
perl_db $DPSCRIPT/getCamstarWafer2AssemblyGenealogy.pl \
  --source_db <DB_CODE> \
  --start_hours <HOURS_AGO_START> \
  --end_hours <HOURS_AGO_END> \
  --out_gen $DPDATA/data/a2w_gen \
  --out_trace $DPDATA/data/a2w_trace \
  --archive_gen $DPDATA/archive/a2w_gen \
  --archive_trace $DPDATA/archive/a2w_trace \
  --logfile $DPLOG/manual_camstar_run.log
```

### Key Arguments
*   **`--source_db`**: The site-specific database code:
    *   `CEBU` (Cebu)
    *   `OSV` (Vietnam)
    *   `SBN` (Malaysia)
    *   `OSPI` (Pico)
    *   `ONSC` (Carmona)
    *   `ONSZ` (Suzhou)
*   **`--start_hours`**: How many hours **ago** to start the search window (e.g., `--start_hours 48`).
*   **`--end_hours`**: How many hours **ago** to end the search window (e.g., `--end_hours 0` for up to current time).

---

## Extracting for a Specific Date (The "Hours Ago" Logic)

Unlike the Snowflake script, this script calculates its extraction window relative to the current time using `getdate()` or `sysdate`. It dose **not** support a `--modfile` or `--start_date` argument.

To extract for a specific historical date (e.g., **2026-02-10**):

1.  **Calculate the offset:**
    *   Current Date: 2026-03-05
    *   Target Date: 2026-02-10
    *   Difference: ~23 days
    *   Calculation: `23 days * 24 hours = 552 hours`.

2.  **Execute command:**
    ```bash
    # To capture a 24-hour window for Feb 10th:
    # Start = (23 days ago) * 24 = 552
    # End = (22 days ago) * 24 = 528
    perl_db $DPSCRIPT/getCamstarWafer2AssemblyGenealogy.pl \
      --source_db OSV \
      --start_hours 552 \
      --end_hours 528 \
      ...
    ```

---

## Troubleshooting "Empty Results"

If the script runs successfully but produces no files for a specific lot, consider these factors:

### 1. The `txnDate` Filter
The script only pulls records where the `historymainline.txnDate` falls within the specified `start_hours` and `end_hours` window.

### 2. Missing Wafer Records
The SQL query (sub `getSQL`) requires an `exists` match in the `A_ConsumeMaterialsHistory` and `A_ConsumeMaterialsHistoryDetai` tables. If the assembly lot exists in Camstar but the wafer consumption records (E142 data) are missing, the script will skip the lot.

### 3. Invalid Scribe IDs
If a lot is found but has an invalid wafer scribe (e.g., containing spaces or not matching RefDB), the script will skip it and log a `WARN: Consumption record will not be written...`.

### 4. RefDB / LOTG Connection
The script relies on several web services and a connection to the `LOTGPRD` Oracle database. If the server cannot reach `globmfgapp.onsemi.com` or the database, lookups for `SOURCE_LOT` and `FAB` will fail, potentially resulting in skipped records.

---

## Python Alternative
A Python port of this script is available at:
`$DPSCRIPT/refdata/n_getCamstarWafer2AssemblyGenealogy.py`

This version can be run similarly for better performance and structured logging, but it uses the same "hours ago" logic as the Perl version.
