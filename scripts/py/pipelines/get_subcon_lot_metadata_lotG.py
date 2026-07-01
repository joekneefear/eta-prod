#!/usr/bin/env python3
"""
Extract SubCon PP_LOT Reference Data (Python version of legacy sqlplus script).

This version now uses the original legacy bash script SQL logic verbatim
(aside from removal of sqlplus formatting / PL/SQL wrapper). It preserves
the original product trimming logic (hyphen only) and does NOT apply the
new underscore-based suffix trimming enhancement.

AUTHOR
   Scott Boothby (SQL Query)
   jgarcia (wrapper script)

CHANGES
    2026-Mar-06 - initial implementation
"""


import os
import sys
import argparse
import time
import logging
import logging.handlers
import json
import gzip
import shutil
import signal
from datetime import datetime, timezone
from pathlib import Path

try:
    SCRIPT_PATH = Path(__file__).resolve()
    SCRIPT_NAME = SCRIPT_PATH.name
except NameError:
    SCRIPT_PATH = None
    SCRIPT_NAME = "getSubconLotRefData_LOTGDB.py"

try:
    import oracledb  # pip install oracledb
except ImportError:
    print("You must install the 'oracledb' package: pip install oracledb")
    sys.exit(1)

try:
    from filelock import FileLock  # pip install filelock
except ImportError:
    print("You must install the 'filelock' package: pip install filelock")
    sys.exit(1)

LOCKFILE = "/tmp/subcon_lot_ref_data_LOTGDB.lock"
EARLY_LOG_FILE = "./log/early.log"

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------

def setup_early_logging():
    os.makedirs("./log", exist_ok=True)
    logger = logging.getLogger("early_logger")
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        fh = logging.FileHandler(EARLY_LOG_FILE, mode="a")
        fh.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
        logger.addHandler(fh)
        ch = logging.StreamHandler()
        ch.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
        logger.addHandler(ch)
    return logger

def remove_early_logging():
    logger = logging.getLogger("early_logger")
    for handler in logger.handlers:
        handler.close()
    logger.handlers.clear()

def setup_logging(log_dir: str, log_file: str, log_level: str = "INFO") -> None:
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, log_file)
    level = getattr(logging, log_level.upper(), logging.INFO)
    root_logger = logging.getLogger()
    for handler in root_logger.handlers[:]:
        handler.close()
        root_logger.removeHandler(handler)
    root_logger.setLevel(level)
    formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
    file_handler = logging.handlers.RotatingFileHandler(
        log_path, maxBytes=20*1024*1024, backupCount=5)
    file_handler.setFormatter(formatter)
    root_logger.addHandler(file_handler)
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)
    logging.info("----- Job started -----")

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

def format_elapsed(elapsed_sec):
    mins, sec = divmod(int(elapsed_sec), 60)
    hrs, mins = divmod(mins, 60)
    result = []
    if hrs:
        result.append(f"{hrs}h")
    if mins:
        result.append(f"{mins}m")
    result.append(f"{sec}s")
    return " ".join(result)

def get_pipeline_info():
    hostname = os.getenv('HOSTNAME', os.getenv('COMPUTERNAME', 'unknown')).lower()
    environment = "prod"
    if any(env_indicator in hostname for env_indicator in ['dev', 'test', 'uat', 'stage']):
        environment = "dev" if 'dev' in hostname else "test"
    environment = os.getenv('PIPELINE_ENV', environment)
    return {
        "pipeline_name": SCRIPT_NAME,
        "script_name": SCRIPT_NAME,
        "pipeline_type": "batch",
        "environment": environment
    }

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract SubCon PP_LOT Reference Data (Python Oracle version, legacy SQL logic).")
    parser.add_argument("oracle_user", help="Oracle DB username (or 'LOTGDB_USER' for default user)")
    parser.add_argument("oracle_password", help="Oracle DB password (ignored if user is 'LOTGDB_USER')")
    parser.add_argument("oracle_sid", help="Oracle SID or service name / connect descriptor")
    parser.add_argument("from_date", nargs="?", help="(optional) From date YYYY-MM-DD")
    parser.add_argument("to_date", nargs="?", help="(optional) To date YYYY-MM-DD")
    parser.add_argument("--reference_data_dir", default=os.getenv("REFERENCE_DATA_DIR", ""), help="Output directory (must exist / be writable)")
    parser.add_argument("--log_dir", default="./log", help="Log directory")
    parser.add_argument("--log_file", default="getSubconLotRefData_LOTGDB.log", help="Log filename")
    parser.add_argument("--log_level", default="INFO", help="Log level")
    parser.add_argument("--benchmark_log_dir", default="./benchmark", help="Benchmark JSONL log dir")
    parser.add_argument("--output_prefix", default="SubconLotRefData", help="Output file prefix")
    parser.add_argument("--archive_dir", default="/apps/exensio_data/archives-yms/reference_data/lot",
                        help="Archive directory (gz the copied file there)")
    parser.add_argument("--pipeline_name", default=SCRIPT_NAME, help="Pipeline name")
    parser.add_argument("--pipeline_type", default="batch", help="Pipeline type")
    parser.add_argument("--environment", help="Environment override (prod/dev/test)")
    parser.add_argument("--no-benchmark", action="store_true", help="Disable benchmark JSONL and Oracle logging entirely")
    parser.add_argument("--benchmark_db_dsn", default=os.getenv("BENCHMARK_DB_DSN") or "exnqa-db.onsemi.com:1740/EXNQA.onsemi.com", help="Oracle DSN for benchmark persistence (optional)")
    parser.add_argument("--benchmark_db_user", nargs="?", const="", default=os.getenv("BENCHMARK_DB_USER"), help="Oracle user for benchmark (default: refdb if flag present)")
    parser.add_argument("--benchmark_db_pass", default=os.getenv("BENCHMARK_DB_PASS"), help="Oracle password for benchmark (optional)")
    return parser.parse_args()

def log_benchmark_jsonl(benchmark_log_dir: str, stats: dict) -> None:
    os.makedirs(benchmark_log_dir, exist_ok=True)
    log_file = os.path.join(benchmark_log_dir, "benchmark.jsonl")
    try:
        with open(log_file, "a", encoding="utf-8") as f:
            json.dump(stats, f)
            f.write('\n')
        logging.info(f"Benchmark logged: pipeline={stats.get('pipeline_name')}, rows={stats.get('rowcount')}, duration={stats.get('elapsed_human')}")
    except Exception as ex:
        logging.error(f"Could not write benchmark log: {ex}")

def log_benchmark_to_oracle(stats: dict, dsn: str, user: str | None = None, password: str | None = None) -> None:
    """
    Insert benchmark data into Oracle pipeline_runs table.
    
    Args:
        stats: Benchmark statistics dictionary
        dsn: Oracle TNS name or connection string
        user: Oracle username (defaults to 'refdb' if not provided)
        password: Oracle password (defaults to hardcoded value if not provided)
    """
    # Use default credentials if not provided
    if not user:
        user = "refdb"
        password = 'br#^gox66312sdAB'
        logging.info("Using default benchmark database credentials (user: %s)", user)
    
    if not password:
        logging.warning("Oracle password not provided, skipping Oracle benchmark insert")
        return
    
    conn = None
    try:
        conn = oracledb.connect(user=user, password=password, dsn=dsn)
        cursor = conn.cursor()
        
        # Prepare metadata JSON
        metadata = {
            "source_name": stats.get("source_name"),
            "output_name": stats.get("output_name"),
            "rows_fetched": stats.get("rows_fetched", 0),
            "rows_kept": stats.get("rows_kept", 0),
            "rows_skipped": stats.get("rows_skipped", 0),
        }
        
        # Serialize arrays/objects to JSON strings for CLOB columns
        metadata_json = json.dumps(metadata)
        benchmark_json = json.dumps(stats)
        
        # Parse timestamps for Oracle (convert ISO 8601 to Oracle format)
        start_local = stats.get("start_local", "")
        end_local = stats.get("end_local", "")
        start_utc = stats.get("start_utc", "")
        end_utc = stats.get("end_utc", "")
        
        sql = """
            INSERT INTO pipeline_runs (
                start_local, end_local, start_utc, end_utc,
                elapsed_seconds, elapsed_human, output_file, rowcount, log_file,
                pid, date_code, pipeline_name, script_name, pipeline_type, environment,
                archived_file, rows_extracted, rows_written, total_files, metadata, benchmark,
                output_files_trace, archived_gen_files, archived_trace_files, out_files,
                status, error_message, hostname, run_args
            ) VALUES (
                TO_TIMESTAMP(:start_local, 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP(:end_local, 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP_TZ(:start_utc, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                TO_TIMESTAMP_TZ(:end_utc, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                :elapsed_seconds, :elapsed_human, :output_file, :rowcount, :log_file,
                :pid, :date_code, :pipeline_name, :script_name, :pipeline_type, :environment,
                :archived_file, :rows_extracted, :rows_written, :total_files, :metadata, :benchmark,
                :output_files_trace, :archived_gen_files, :archived_trace_files, :out_files,
                :status, :error_message, :hostname, :run_args
            )
        """
        
        # Get hostname and run arguments
        import socket
        hostname = socket.gethostname()
        run_args = " ".join(sys.argv)
        
        cursor.execute(sql, {
            "start_local": start_local,
            "end_local": end_local,
            "start_utc": start_utc,
            "end_utc": end_utc,
            "elapsed_seconds": stats.get("elapsed_seconds"),
            "elapsed_human": stats.get("elapsed_human"),
            "output_file": stats.get("output_file") or "N/A",
            "rowcount": stats.get("rowcount"),
            "log_file": stats.get("log_file") or "N/A",
            "pid": stats.get("pid"),
            "date_code": stats.get("date_code"),
            "pipeline_name": stats.get("pipeline_name"),
            "script_name": stats.get("script_name"),
            "pipeline_type": stats.get("pipeline_type"),
            "environment": stats.get("environment"),
            "archived_file": stats.get("archived_file") or "N/A",
            "rows_extracted": stats.get("rows_extracted"),
            "rows_written": stats.get("rows_written"),
            "total_files": stats.get("total_files"),
            "metadata": metadata_json,
            "benchmark": benchmark_json,
            "output_files_trace": "[]",
            "archived_gen_files": "[]",
            "archived_trace_files": "[]",
            "out_files": json.dumps(stats.get("out_files", [])),
            "status": stats.get("status", "success"),
            "error_message": stats.get("error_message", ""),
            "hostname": hostname,
            "run_args": run_args,
        })
        
        conn.commit()
        logging.info("Benchmark data inserted into Oracle pipeline_runs table")
        
    except Exception as ex:
        logging.error("Failed to insert benchmark into Oracle: %s", ex)
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass

def archive_and_compress(file_path, archive_dir):
    if not archive_dir:
        return
    os.makedirs(archive_dir, exist_ok=True)
    basename = os.path.basename(file_path)
    gz_path = os.path.join(archive_dir, basename + ".gz")
    gz_path_tmp = gz_path + ".tmp"
    try:
        with open(file_path, "rb") as f_in, gzip.open(gz_path_tmp, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)
            f_out.flush()
            os.fsync(f_out.fileobj.fileno())
        os.replace(gz_path_tmp, gz_path)
        gz_abs = os.path.abspath(gz_path)
        logging.info(f"Archived and compressed {gz_abs}")
    except Exception as e:
        logging.error(f"Failed to archive/compress: {e}")
        if os.path.exists(gz_path_tmp):
            os.remove(gz_path_tmp)
        return None
    return gz_abs

def get_oracle_connection(user, password, dsn):
    try:
        return oracledb.connect(user=user, password=password, dsn=dsn)
    except Exception:
        logging.error("Failed to connect to Oracle DB.")
        raise

# ---------------------------------------------------------------------------
# Legacy SQL builder (faithful to original bash script)
# ---------------------------------------------------------------------------

def build_sql_and_header_legacy(time_interval: str):
    """
    Returns the legacy SQL (copied from the original bash script logic) plus header metadata.
    Only change applied: insertion of the dynamic time interval.
    """
    sql_query = f"""
    WITH lot_classes AS
    (
        SELECT /*+ MATERIALIZE */ UNIQUE LOTCLASS_CD
        FROM LOTG_OWNER.LOT_CLASS
        WHERE DESCRIPTION NOT LIKE 'INVENTORY CONV%'
    )
    , src_tgt_xref_with AS
    (
        SELECT
            FROM_BANK_CODE,
            TO_BANK_CODE,
            REVERSAL_FLAG,
            FK_GENEALOGY_MAFK AS PARENT_PART_ID,
            FK_GENEALOGY_MACLA AS PARENT_LOT_CLASS,
            FK_GENEALOGY_MAIDE AS PARENT_LOT_NUM,
            FK_GENEALOGY_MANOD AS PARENT_TRANSDATE,
            FK_GENEALOGY_MANOT AS PARENT_TRANSTIME,
            FK0GENEALOGY_MAFK  AS PART_ID,
            FK0GENEALOGY_MACLA AS LOT_CLASS,
            FK0GENEALOGY_MAIDE AS LOT_NUM,
            FK1GENEALOGY_MANOD AS TRANSDATE,
            FK1GENEALOGY_MANOT AS TRANSTIME,
            POST_DATE,
            POST_TIME
        FROM LOTG_OWNER.SRC_TGT_XREF
    )
    , lot_ref AS (
        SELECT /*+ MATERIALIZE INDEX(v SRC_POSTDATE) */ UNIQUE
              REGEXP_SUBSTR(FK0GENEALOGY_MAIDE, '([^-]+)?', 1, 1,'i') AS LOT
            , v.FK0GENEALOGY_MAFK AS PART_ID
            , v.FK0GENEALOGY_MACLA AS LOT_CLASS
            , REGEXP_SUBSTR(
                CASE WHEN FK_GENEALOGY_MACLA LIKE 'B%' OR
                          COALESCE(ip.type, ppi.PART_TYPE) NOT IN ('WFR','DIE','WAFER','BAS','Diced Part','WDQ Part','Wafer Fab Part','Wafer Post Fab Part') OR
                          v.FK_GENEALOGY_MAIDE LIKE 'SND%'
                     THEN FK0GENEALOGY_MAIDE
                     ELSE FK_GENEALOGY_MAIDE END,
                '([^-]+)?', 1, 1,'i') AS PARENT_LOT
            , CASE WHEN COALESCE(ip.type, ppi.PART_TYPE) NOT IN ('WFR','DIE','WAFER','BAS','Diced Part','WDQ Part','Wafer Fab Part','Wafer Post Fab Part')
                        OR FK_GENEALOGY_MACLA LIKE 'B%'
                        OR v.FK_GENEALOGY_MAIDE LIKE 'SND%'
                   THEN v.FK0GENEALOGY_MAFK
                   ELSE FK_GENEALOGY_MAFK END AS PARENT_PART_ID
            , CASE WHEN lcc.DESCRIPTION LIKE '%ENG%' THEN 'E' ELSE 'P' END AS LOT_OWNER
            , DENSE_RANK() OVER (
                  PARTITION BY REGEXP_SUBSTR(FK0GENEALOGY_MAIDE, '([^-]+)?', 1, 1,'i')
                  ORDER BY v.FK1GENEALOGY_MANOD, v.FK1GENEALOGY_MANOT
              ) AS DR
        FROM LOTG_OWNER.SRC_TGT_XREF v
            LEFT JOIN LOTG_OWNER.LOT_CLASS lcc ON v.FK0GENEALOGY_MACLA = lcc.LOTCLASS_CD
            LEFT JOIN LOTG_OWNER.LOTG_BOM_TYPE ip ON v.FK_GENEALOGY_MAFK = ip.PART
            JOIN LOTG_OWNER.PC_ITEM ppi ON v.FK_GENEALOGY_MAFK = ppi.PART_ID
            JOIN LOTG_OWNER.PC_ITEM pi ON v.FK0GENEALOGY_MAFK = pi.PART_ID
        WHERE v.FK0GENEALOGY_MACLA IN (SELECT LOTCLASS_CD FROM lot_classes)
          {time_interval}
          AND pi.PART_TYPE IN ('Wafer Post Fab Part','Wafer Fab Part','WDQ Part')
          AND NOT (v.FROM_BANK_CODE = 'XFCS' AND v.FK0GENEALOGY_MAIDE = v.FK_GENEALOGY_MAIDE)
          AND NOT EXISTS (
              SELECT 1
              FROM src_tgt_xref_with vx
              WHERE v.FK0GENEALOGY_MAIDE != v.FK_GENEALOGY_MAIDE
                AND vx.LOT_NUM = v.FK0GENEALOGY_MAIDE
                AND vx.PARENT_LOT_NUM != v.FK_GENEALOGY_MAIDE
                AND vx.TRANSDATE = v.FK1GENEALOGY_MANOD
                AND vx.TRANSTIME = v.FK1GENEALOGY_MANOT
                AND vx.PART_ID = v.FK0GENEALOGY_MAFK
                AND vx.PARENT_PART_ID = v.FK_GENEALOGY_MAFK
          )
          AND v.FK0GENEALOGY_MACLA NOT LIKE 'B%'
    )
    , walk AS
    (
        SELECT /*+ MATERIALIZE */ UNIQUE w.*
        FROM (
            SELECT LOT_NUM, LOT_CLASS, PART_ID,
                   PARENT_LOT_NUM, PARENT_LOT_CLASS, PARENT_PART_ID,
                   TRANS_DT, PARENT_TRANS_DT,
                   CONNECT_BY_ROOT lot_num AS TOP
            FROM (
                SELECT LOT_NUM, LOT_CLASS, PART_ID,
                       CASE WHEN REGEXP_LIKE(PARENT_LOT_NUM, '^M0.+\\d[A-Z]$')
                            THEN SUBSTR(PARENT_LOT_NUM, 1, LENGTH(PARENT_LOT_NUM)-1)
                            WHEN REGEXP_LIKE(PARENT_LOT_NUM, '^PW.+\\d+[A-Z]$')
                            THEN SUBSTR(PARENT_LOT_NUM, 1, LENGTH(PARENT_LOT_NUM)-1)
                            ELSE PARENT_LOT_NUM END AS PARENT_LOT_NUM,
                       PARENT_LOT_CLASS, PARENT_PART_ID,
                       TO_DATE(TO_CHAR(TRANSDATE,'YYYY-MM-DD') || ' ' || SUBSTR(TRANSTIME,1,4),'YYYY-MM-DD HH24MI')
                         + CAST(SUBSTR(TRANSTIME,5,2) AS INT)*INTERVAL '1' SECOND AS TRANS_DT,
                       TO_DATE(TO_CHAR(PARENT_TRANSDATE,'YYYY-MM-DD') || ' ' || SUBSTR(PARENT_TRANSTIME,1,4),'YYYY-MM-DD HH24MI')
                         + CAST(SUBSTR(PARENT_TRANSTIME,5,2) AS INT)*INTERVAL '1' SECOND AS PARENT_TRANS_DT
                FROM src_tgt_xref_with v
                WHERE NOT EXISTS (
                    SELECT 1 FROM src_tgt_xref_with vx
                    WHERE vx.LOT_NUM = v.LOT_NUM
                      AND vx.PARENT_LOT_NUM != v.PARENT_LOT_NUM
                      AND vx.TRANSDATE = v.TRANSDATE
                      AND vx.TRANSTIME = v.TRANSTIME
                      AND vx.PART_ID = v.PART_ID
                      AND vx.PARENT_PART_ID = v.PARENT_PART_ID
                )
                  AND PARENT_LOT_NUM NOT LIKE 'SND%'
            ) v
            CONNECT BY NOCYCLE PRIOR PARENT_PART_ID = PART_ID
                               AND PRIOR PARENT_LOT_NUM = LOT_NUM
            START WITH EXISTS(
                SELECT 1 FROM lot_ref sl
                WHERE sl.PARENT_LOT = v.LOT_NUM AND sl.DR=1
            )
        ) w
        LEFT JOIN LOTG_OWNER.PC_ITEM i ON w.PARENT_PART_ID = i.PART_ID
        WHERE i.PART_TYPE NOT IN ('Substrate Part','Ingot Part','PolySilicon Part')
          AND w.PARENT_PART_ID NOT LIKE '%-BAS'
    )
    , translate AS (
        SELECT UNIQUE
            REGEXP_SUBSTR(w.LOT_NUM,'([^-]+)?',1,1,'i') AS LOT,
            LOT_CLASS,
            CASE WHEN lcc.DESCRIPTION LIKE '%ENG%' THEN 'E' ELSE 'P' END AS LOT_OWNER,
            REGEXP_REPLACE(
                CASE
                  WHEN (REGEXP_LIKE(w.PART_ID,'^.+-.+-...$')
                        OR REGEXP_LIKE(w.PART_ID,'^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)$'))
                       THEN SUBSTR(w.PART_ID,1,INSTR(w.PART_ID,'-',-1)-1)
                  ELSE w.PART_ID END,
                '-', '_'
            ) AS PRODUCT,
            COALESCE(cbt.TYPE,'UNK') AS BOM_PART_TYPE,
            i.PART_TYPE,
            REGEXP_SUBSTR(w.PARENT_LOT_NUM,'([^-]+)?',1,1,'i') AS PARENT_LOT,
            PARENT_LOT_CLASS,
            REGEXP_REPLACE(
                CASE
                  WHEN (REGEXP_LIKE(w.PARENT_PART_ID,'^.+-.+-...$')
                        OR REGEXP_LIKE(w.PARENT_PART_ID,'^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)$'))
                       THEN SUBSTR(w.PARENT_PART_ID,1,INSTR(w.PARENT_PART_ID,'-',-1)-1)
                  ELSE w.PARENT_PART_ID END,
                '-', '_'
            ) AS PARENT_PRODUCT,
            COALESCE(pbt.TYPE,'UNK') AS PARENT_PART_TYPE,
            TRANS_DT
        FROM walk w
          LEFT JOIN LOTG_OWNER.LOTG_BOM_TYPE pbt ON w.PARENT_PART_ID = pbt.PART
          LEFT JOIN LOTG_OWNER.PC_ITEM i ON w.PART_ID = i.PART_ID
          LEFT JOIN LOTG_OWNER.LOTG_BOM_TYPE cbt ON w.PART_ID = cbt.PART
          LEFT JOIN LOTG_OWNER.LOT_CLASS lcc ON w.LOT_CLASS = lcc.LOTCLASS_CD
    )
    , src_lot_walk AS
    (
        SELECT LOT, PRODUCT, PARENT_LOT, PARENT_PRODUCT, CONNECT_BY_ROOT LOT AS TOP,
               RANK() OVER (PARTITION BY CONNECT_BY_ROOT LOT ORDER BY TRANS_DT) AS DR
        FROM translate w
        CONNECT BY NOCYCLE PRIOR PARENT_PRODUCT = PRODUCT
                           AND PRIOR PARENT_LOT = LOT
        START WITH PART_TYPE IN ('Wafer Post Fab Part','Wafer Fab Part','WDQ Part')
        UNION ALL
        SELECT PARENT_LOT AS LOT, PARENT_PRODUCT AS PRODUCT,
               PARENT_LOT, PARENT_PRODUCT, PARENT_LOT AS TOP, 1 AS DR
        FROM translate w1
        WHERE NOT EXISTS (
            SELECT 1 FROM translate w2
            WHERE w1.PARENT_PRODUCT = w2.PRODUCT
              AND w1.PARENT_LOT = w2.LOT
        )
    )
    , src_lot AS
    (
        SELECT UNIQUE TOP AS LOT, PARENT_LOT AS SOURCE_LOT, PARENT_PRODUCT
        FROM src_lot_walk w
        WHERE DR = 1
    )
    SELECT UNIQUE
        l.LOT,
        LOT_CLASS,
        PARENT_LOT,
        REGEXP_REPLACE(
            CASE
              WHEN (REGEXP_LIKE(PART_ID,'^.+-.+-...$')
                    OR REGEXP_LIKE(PART_ID,'^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)$'))
                THEN SUBSTR(PART_ID,1,INSTR(PART_ID,'-',-1)-1)
              ELSE PART_ID END,
            '-', '_'
        ) AS PRODUCT,
        REGEXP_REPLACE(
            CASE
              WHEN (REGEXP_LIKE(sl.PARENT_PRODUCT,'^.+-.+-...$')
                    OR REGEXP_LIKE(sl.PARENT_PRODUCT,'^.+-(ASM|ASY|WDQ|FAB|DSG|EPC|ECH|DFF|SCB|UTP|BMP|WFA|WBP|WPR|BSM|FSM|SWF|FTP|TST|XTD|FTD|APT|UTD|EPT|EPU|XTP|WAF|DIE|XWF|THN|FMD|XMD|EPM|BAS|DWR|NRE|XDW|GLD|XDI|XDS|EPD|DST|EPA|EPW)$'))
                THEN SUBSTR(sl.PARENT_PRODUCT,1,INSTR(sl.PARENT_PRODUCT,'-',-1)-1)
              ELSE sl.PARENT_PRODUCT END,
            '-', '_'
        ) AS PARENT_PRODUCT,
        LOT_OWNER,
        COALESCE(sl.SOURCE_LOT, PARENT_LOT, ' ') AS SOURCE_LOT
    FROM lot_ref l
      LEFT JOIN src_lot sl ON l.PARENT_LOT = sl.LOT
    WHERE l.DR = 1
    ORDER BY l.LOT
    """
    header = ["LOT", "LOT_CLASS", "PARENT_LOT", "PRODUCT", "PARENT_PRODUCT", "LOT_OWNER", "SOURCE_LOT"]
    return sql_query, header

# ---------------------------------------------------------------------------
# Writer (unchanged: still collapses PRODUCT in output)
# ---------------------------------------------------------------------------

def atomic_write_sqlplus_compatible(output_path, cursor, write_header=True):
    """
    Write final 5-column output matching legacy spool:
      LOT|PARENT_LOT|PRODUCT|LOT_OWNER|SOURCE_LOT
    PRODUCT = COALESCE(PARENT_PRODUCT, PRODUCT)
    """
    tmp_path = output_path + ".tmp"
    rowcount = 0
    with open(tmp_path, "w", encoding="utf-8", buffering=1) as outf:
        if write_header:
            outf.write("LOT|PARENT_LOT|PRODUCT|LOT_OWNER|SOURCE_LOT\n")
        for rows in iter(lambda: cursor.fetchmany(cursor.arraysize), []):
            for lot, _lot_class, parent_lot, product, parent_product, lot_owner, source_lot in rows:
                final_product = parent_product or product or ""
                outf.write(f"{lot or ''}|{parent_lot or ''}|{final_product}|{lot_owner or ''}|{source_lot or ''}\n")
                rowcount += 1
        outf.flush()
        os.fsync(outf.fileno())
    os.replace(tmp_path, output_path)
    return rowcount

# ---------------------------------------------------------------------------
# Graceful exit & main
# ---------------------------------------------------------------------------

def graceful_exit(lock):
    if lock:
        lock.release()
    logging.info("Script interrupted. Lock released.")
    sys.exit(130)

def main():
    early_logger = setup_early_logging()
    lock = None

    def sig_handler(signum, frame):
        graceful_exit(lock)

    signal.signal(signal.SIGINT, sig_handler)
    signal.signal(signal.SIGTERM, sig_handler)

    try:
        args = parse_args()
        setup_logging(args.log_dir, args.log_file, args.log_level)
        remove_early_logging()

        pipeline_info = get_pipeline_info()
        if args.pipeline_name != SCRIPT_NAME:
            pipeline_info["pipeline_name"] = args.pipeline_name
        if args.pipeline_type != "batch":
            pipeline_info["pipeline_type"] = args.pipeline_type
        if args.environment:
            pipeline_info["environment"] = args.environment

        logging.info(
            f"Pipeline: {pipeline_info['pipeline_name']} | Type: {pipeline_info['pipeline_type']} "
            f"| Environment: {pipeline_info['environment']} | Script: {SCRIPT_NAME}"
        )

        # Directory validation
        for d in [args.reference_data_dir, args.benchmark_log_dir, args.log_dir]:
            if not d:
                logging.error(f"Directory argument is empty: {d}")
                print(f"Directory argument is empty: {d}", file=sys.stderr)
                sys.exit(1)
            os.makedirs(d, exist_ok=True)

        lock = FileLock(LOCKFILE)
        lock.acquire(timeout=0)

        if args.oracle_user == "LOTGDB_USER":
            oracle_user = "LOTG_READ"
            oracle_password = os.getenv("LOTG_PASS") or "prdlotgr"
        else:
            oracle_user = args.oracle_user
            oracle_password = args.oracle_password

        if args.from_date and args.to_date:
            time_interval = (
                f"and POST_DATE between TO_DATE('{args.from_date}', 'YYYY-MM-DD') "
                f"AND TO_DATE('{args.to_date} 23:59:59', 'YYYY-MM-DD HH24:MI:SS')"
            )
            date_code = f"{args.from_date}_{args.to_date}"
        else:
            time_interval = "and POST_DATE >= sysdate - 32*interval '1' hour"
            date_code = datetime.now().strftime("%Y%m%d_%H%M%S")

        out_file = os.path.join(
            args.reference_data_dir,
            f"{args.output_prefix}-{date_code}.subconLot"
        )

        sql_query, header = build_sql_and_header_legacy(time_interval)
        dsn = args.oracle_sid
        start_time = time.time()
        start_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        start_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        logging.info(f"Running Oracle query export to {out_file} (legacy logic) ...")

        try:
            conn = get_oracle_connection(oracle_user, oracle_password, dsn)
        except Exception:
            sys.exit(2)

        rowcount = 0
        try:
            with conn.cursor() as cur:
                cur.execute("alter session set nls_date_format = 'YYYY-MM-DD HH24:MI:SS'")
                cur.arraysize = 10000
                cur.execute(sql_query)
                if cur.description is None:
                    logging.error("The executed statement returned no result set.")
                    print("The executed statement returned no result set.", file=sys.stderr)
                    sys.exit(2)
                rowcount = atomic_write_sqlplus_compatible(out_file, cur, write_header=True)
        except Exception as e:
            logging.error(f"Error during export: {e}")
            sys.exit(2)
        finally:
            try:
                conn.close()
            except Exception:
                pass

        elapsed = time.time() - start_time
        end_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        end_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        human_elapsed = format_elapsed(elapsed)
        archived_file = 'NA'

        if os.path.exists(out_file) and rowcount > 0:
            logging.info(f"Oracle export succeeded: {out_file} ({rowcount} rows; data rows only)")
            logging.info(f"Elapsed time: {human_elapsed} ({elapsed:.3f} seconds)")
            if args.archive_dir:
                archived_path = archive_and_compress(out_file, args.archive_dir)
                if archived_path:
                    archived_file = archived_path  # store absolute path to .gz for JSONL
        else:
            logging.error("Oracle export failed or produced empty file.")
            sys.exit(2)

        out_files = [{"path": os.path.abspath(out_file), "rows": rowcount}]
        if archived_file != 'NA':
            out_files.append({"path": os.path.abspath(archived_file), "rows": rowcount})

        rows_fetched = rowcount
        rows_kept = rowcount
        rows_skipped = 0
        source_name = "LotG Subcon Lot Metadata"
        output_name = os.path.basename(out_file)

        stats = {
            "start_local": start_local,
            "end_local": end_local,
            "start_utc": start_utc,
            "end_utc": end_utc,
            "elapsed_seconds": round(elapsed, 3),
            "elapsed_human": human_elapsed,
            "output_file": os.path.abspath(out_file),
            "rowcount": rowcount,
            "rows_extracted": rowcount,
            "rows_written": rowcount,
            "rows_fetched": rows_fetched,
            "rows_kept": rows_kept,
            "rows_skipped": rows_skipped,
            "source_name": source_name,
            "output_name": output_name,
            "total_files": len(out_files),
            "out_files": out_files,
            "log_file": os.path.join(args.log_dir, args.log_file),
            "archived_file": archived_file,  # full path to the .gz file (or 'NA' if not archived)
            "pid": os.getpid(),
            "date_code": date_code,
            "pipeline_name": pipeline_info["pipeline_name"],
            "script_name": pipeline_info["script_name"],
            "pipeline_type": pipeline_info["pipeline_type"],
            "environment": pipeline_info["environment"],
            "status": "success",
            "error_message": ""
        }
        
        if not getattr(args, "no_benchmark", False):
            log_benchmark_jsonl(args.benchmark_log_dir, stats)
            logging.info(f"Benchmark log appended to {args.benchmark_log_dir}/benchmark.jsonl")
            
            if args.benchmark_db_dsn:
                log_benchmark_to_oracle(
                    stats=stats,
                    dsn=args.benchmark_db_dsn,
                    user=args.benchmark_db_user,
                    password=args.benchmark_db_pass
                )
                
        logging.info("----- Job finished -----")
    finally:
        if lock:
            lock.release()

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.critical(f"Uncaught error: {e}", exc_info=True)
        print(f"Script failed: {e}", file=sys.stderr)
        sys.exit(3)