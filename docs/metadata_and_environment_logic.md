# Lot Metadata and Environment Detection Logic

This document details how the Python preprocessing system retrieves lot metadata and decides whether to route processed files to **PRODUCTION** or **SANDBOX** environments.

## 1. Lot Metadata Retrieval
The system uses a multi-tiered lookup strategy to gather essential lot attributes (e.g., `TPNO`, `Technology`, `Fab`, `SourceLot`).

### Lookup Hierarchy
1.  **Local Metadata File (`.lot`)**: 
    - The script first checks for a local CSV file named `{MotherLot}.lot` in the path specified by the `lot_metadata_location` configuration.
    - Handled by `JndUtil.load_jnd_lot_metadata`.
2.  **External API (ERT)**:
    - If local data is insufficient or missing, the system queries the **Refdb API (ERT)**.
    - Endpoints include `onlot`, `onscribe`, and `onprod` service URLs configured via `ws_url_ref_data`.
    - Handled by `RefdbAPIClient` and methods in `JndUtil`.
3.  **Filename Parsing**:
    - If lookups fail, the Lot ID is extracted directly from the input filename using regular expressions.
    - Handled by `JndUtil.extract_lot_from_jnd_pcm_filename`.
4.  **Default Values**:
    - As a fallback, default metadata structures defined in the YAML config are used to prevent script failure.

---

## 2. Production vs. Sandbox Routing
The routing decision is controlled by the `Writer` class (`lib/Writer.py`) based on the state of specific flags during execution.

### Logic Flow in `Writer.outfile()`

| Flag | Trigger Condition | Target Directory |
| :--- | :--- | :--- |
| **`noMeta`** | Set to `True` if essential metadata lookup fails or returns `NA`. | `SANDBOX` |
| **`wmapIsEmpty`** | Set to `True` if the wafer map processing yields no valid data. | `SANDBOX` |
| **`forced_sandbox`**| A manual override (usually passed via `--forced_sandbox` CLI arg). | `SANDBOX` |
| **`qde`** | Set to `True` for Quality Data Entry processing. | `QDE` |
| *None* | Default successful processing path. | **`PRODUCTION`** |

### Logging and Persistence
The decision and the reasons for it are logged to the `refdb.pp_log` table via the `PPLogger` class.
- Log messages containing "ERROR", "WARNING", or "metadata" are prioritized for persistence.
- Output directories and environment codes are captured to provide a clear audit trail of why a lot ended up in SANDBOX.
