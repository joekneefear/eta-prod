# Manual Extraction Guide: getSnowflakeE142ModuleTrace.pl

This guide explains how to manually trigger E142 trace extractions from Snowflake using the Perl script directly. This is useful for re-running failed extractions or capturing specific historical data windows.

## Core Command Structure

To run the script directly, you must use the `perl_db` interpreter (which contains the necessary DBI and Snowflake drivers).

```bash
perl_db $DPSCRIPT/getSnowflakeE142ModuleTrace.pl \
  --source_odbc MART_SNOWFLAKE \
  --source_warehouse MFG_PRD_RPT_WH \
  --source_schema ANALYTICSPRD.MFG \
  --view_name <VIEW_NAME> \
  --flow <FLOW> \
  --stage <STAGE> \
  --modfile <PATH_TO_MODFILE> \
  --max_hours <HOURS> \
  --out_trace <OUTPUT_DIR> \
  --logfile <LOG_FILE>
```

### Required Arguments for Manual Runs
*   **`--view_name`**: The Snowflake view (e.g., `E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT`).
*   **`--flow`**: `B1T` (for VN5) or `PIM` (for MY1/CNG).
*   **`--stage`**: See [Stage Mapping](#stage-mapping).
*   **`--modfile`**: Path to a text file containing the start timestamp (Format: `YYYY-MM-DD HH24:MI:SS`).
*   **`--max_hours`**: The duration of the search window starting from the modfile timestamp.

---

## Stage Mapping

The `--stage` argument determines which Snowflake columns are queried and the extension of the resulting `.gz` file.

| Stage Name | Flow Type | Extension | Common Usage |
| :--- | :--- | :--- | :--- |
| **`WAFER`** | Forward | `.w2f.gz` | Wafer Fab to Assembly |
| **`TEST`** | Backward | `.f2w.gz` | **Final Test to Wafer (FT2Wafer)** |
| **`DIEBOND`** | Backward | `.a2w.gz` | Assembly to Wafer |
| **`SINGULATION`**| Backward | `.s2w.gz` | Singulation to Wafer |
| **`LEADFRAME_ATTACH`** | Backward | `.fa2w.gz` | Frame Attach to Wafer |

---

## The "Time Window" Logic (Troubleshooting)

The most common reason for a "successful" run with zero files generated is a mismatch between the `--modfile` timestamp and the data availability in Snowflake.

### How it works:
1.  The script reads the timestamp from the `--modfile`.
2.  It calculates a **Lot-Level Window**: It finds the `max(METAMODIFIEDDATE)` for *every* die in a lot.
3.  **The Filter:** The lot is only extracted if its **latest update** in Snowflake falls between:
    *   `START`: Timestamp in your modfile.
    *   `END`: `START` + `max_hours`.

### Example Discrepancy (VU06A0* Lots):
If you run for `2026-02-10` with `--max_hours 24`, but the data was only uploaded/updated in Snowflake on `2026-02-23`, the script will skip those lots because Feb 23 is outside the Feb 10-11 window.

**To verify availability, run this in Snowflake:**
```sql
SELECT TEST_LOT, MAX(METAMODIFIEDDATE) as LAST_UPDATE
FROM ANALYTICSPRD.MFG.E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT
WHERE TEST_LOT IN ('VU06A0M3', 'VU06A0K9', ...)
GROUP BY TEST_LOT;
```

---

## Execution Examples

### 1. Extracting FT2Wafer (TEST stage) for a specific day
```bash
# 1. Create the date marker
echo "2026-02-23 00:00:00" > /tmp/start_date.txt

# 2. Run the extraction
perl_db $DPSCRIPT/getSnowflakeE142ModuleTrace.pl \
  --source_odbc MART_SNOWFLAKE \
  --source_warehouse MFG_PRD_RPT_WH \
  --source_schema ANALYTICSPRD.MFG \
  --view_name E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT \
  --flow B1T \
  --stage TEST \
  --modfile /tmp/start_date.txt \
  --max_hours 24 \
  --out_trace /export/home/dpower/data/e142_trace \
  --logfile $DPLOG/manual_test_run.log
```

### 2. Including Product Names
Add the `--get_product` flag to include product names in the output files. Note that if the product is excluded by headers or reg-ex (e.g., `^NVG.+`), it may be skipped.

---

## Technical Notes
*   **Locking**: The script uses a lock file (e.g., `/tmp/n_getSnowflakeE142ModuleTrace.lock`) to prevent concurrent runs. If a manual run fails to start, check for an existing lock.
*   **Environment**: Ensure `SNOW_USER` and `SNOW_PASS` are exported in your shell.
