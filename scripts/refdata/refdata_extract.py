#!/usr/bin/env python3
"""
Universal refdata extract runner.

- Uses Snowflake via connector or ODBC DSN.
- Runs SQL from file with :param placeholders.
- Writes pipe-delimited output and benchmark JSONL.
"""

import os
import sys
import argparse
import time
import json
import gzip
import shutil
import logging
import logging.handlers
import re
from datetime import datetime, timezone
from pathlib import Path

try:
    import snowflake.connector  # pip install snowflake-connector-python
except ImportError:
    snowflake = None

try:
    import pyodbc  # pip install pyodbc
except ImportError:
    pyodbc = None

try:
    import oracledb  # pip install oracledb
except ImportError:
    oracledb = None

try:
    import yaml  # pip install pyyaml
except ImportError:
    yaml = None

try:
    SCRIPT_PATH = Path(__file__).resolve()
    SCRIPT_NAME = SCRIPT_PATH.name
except NameError:
    SCRIPT_PATH = None
    SCRIPT_NAME = "refdata_extract.py"

EARLY_LOG_FILE = "./log/early.log"


def setup_early_logging():
    os.makedirs("./log", exist_ok=True)
    logger = logging.getLogger("early_logger")
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        fh = logging.FileHandler(EARLY_LOG_FILE, mode="a")
        fh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(fh)
        ch = logging.StreamHandler()
        ch.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
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
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    file_handler = logging.handlers.RotatingFileHandler(
        log_path, maxBytes=20 * 1024 * 1024, backupCount=5
    )
    file_handler.setFormatter(formatter)
    root_logger.addHandler(file_handler)
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)
    logging.info("----- Job started -----")


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
    hostname = os.getenv("HOSTNAME", os.getenv("COMPUTERNAME", "unknown")).lower()
    environment = "prod"
    if any(env_indicator in hostname for env_indicator in ["dev", "test", "uat", "stage"]):
        environment = "dev" if "dev" in hostname else "test"
    environment = os.getenv("PIPELINE_ENV", environment)
    return {
        "pipeline_name": SCRIPT_NAME,
        "script_name": SCRIPT_NAME,
        "pipeline_type": "batch",
        "environment": environment,
    }


def log_benchmark_jsonl(benchmark_log_dir: str, stats: dict) -> None:
    os.makedirs(benchmark_log_dir, exist_ok=True)
    log_file = os.path.join(benchmark_log_dir, "benchmark.jsonl")
    try:
        with open(log_file, "a", encoding="utf-8") as f:
            json.dump(stats, f)
            f.write("\n")
        logging.info(
            "Benchmark logged: pipeline=%s, rows=%s, duration=%s",
            stats.get("pipeline_name"),
            stats.get("rowcount"),
            stats.get("elapsed_human"),
        )
    except Exception as ex:
        logging.error("Could not write benchmark log: %s", ex)


def log_benchmark_to_oracle(stats: dict, dsn: str, user: str = None, password: str = None) -> None:
    """
    Insert benchmark data into Oracle pipeline_runs table.
    
    Args:
        stats: Benchmark statistics dictionary
        dsn: Oracle TNS name or connection string
        user: Oracle username (defaults to 'refdb' if not provided)
        password: Oracle password (defaults to hardcoded value if not provided)
    """
    if not oracledb:
        logging.warning("oracledb package not installed, skipping Oracle benchmark insert")
        return
    
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
        }
        
        # Serialize arrays/objects to JSON strings for CLOB columns
        metadata_json = json.dumps(metadata)
        benchmark_json = json.dumps(stats)
        
        # Parse timestamps for Oracle (convert ISO 8601 to Oracle format)
        start_local = stats.get("start_local", "")
        end_local = stats.get("end_local", "")
        start_utc = stats.get("start_utc", "").replace("T", " ").replace("Z", "")
        end_utc = stats.get("end_utc", "").replace("T", " ").replace("Z", "")
        
        sql = """
            INSERT INTO pipeline_runs (
                start_local, end_local, start_utc, end_utc,
                elapsed_seconds, elapsed_human, output_file, rowcount, log_file,
                pid, date_code, pipeline_name, script_name, pipeline_type, environment,
                archived_file, rows_extracted, rows_written, total_files, metadata, benchmark
            ) VALUES (
                TO_TIMESTAMP_TZ(:start_local, 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP_TZ(:end_local, 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP_TZ(:start_utc, 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP_TZ(:end_utc, 'YYYY-MM-DD HH24:MI:SS'),
                :elapsed_seconds, :elapsed_human, :output_file, :rowcount, :log_file,
                :pid, :date_code, :pipeline_name, :script_name, :pipeline_type, :environment,
                :archived_file, :rows_extracted, :rows_written, :total_files, :metadata, :benchmark
            )
        """
        
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
        return None
    os.makedirs(archive_dir, exist_ok=True)
    basename = os.path.basename(file_path)
    gz_path = os.path.join(archive_dir, basename + ".gz")
    gz_path_tmp = gz_path + ".tmp"
    try:
        with open(file_path, "rb") as f_in, gzip.open(gz_path_tmp, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)
        os.replace(gz_path_tmp, gz_path)
        gz_abs = os.path.abspath(gz_path)
        logging.info("Archived and compressed %s", gz_abs)
        return gz_abs
    except Exception as e:
        logging.error("Failed to archive/compress: %s", e)
        if os.path.exists(gz_path_tmp):
            os.remove(gz_path_tmp)
        return None


def read_sql_file(sql_file: str) -> str:
    with open(sql_file, "r", encoding="utf-8") as f:
        return f.read()


def parse_params(params_json: str | None, params_file: str | None) -> dict:
    if params_json and params_file:
        raise ValueError("Use only one of --params_json or --params_file")
    if params_file:
        with open(params_file, "r", encoding="utf-8") as f:
            return json.load(f)
    if params_json:
        return json.loads(params_json)
    return {}


def prepare_sql_with_params(sql: str, params: dict) -> tuple[str, list]:
    """
    Convert :named parameters to qmark placeholders and return ordered values.
    Skips :: casts using a negative lookbehind.
    """
    param_names: list[str] = []

    # We must ignore :tokens that appear inside single-quoted string literals
    # (e.g. the Oracle format 'HH24:MI:SS' contains :MI which is NOT a param).
    out_chars: list[str] = []
    i = 0
    L = len(sql)
    in_sq = False
    while i < L:
        ch = sql[i]
        if ch == "'":
            # enter or exit single-quote literal; handle doubled quotes
            in_sq = not in_sq
            out_chars.append(ch)
            i += 1
            # copy until closing quote (respect doubled single quotes)
            while i < L and in_sq:
                out_chars.append(sql[i])
                if sql[i] == "'":
                    # if next char is also a quote it's an escaped quote
                    if i + 1 < L and sql[i + 1] == "'":
                        # keep both and advance
                        out_chars.append(sql[i + 1])
                        i += 2
                        continue
                    else:
                        in_sq = False
                        i += 1
                        break
                i += 1
            continue

        # match :name when not preceded by ':' (skip :: casts) and not in quote
        if ch == ":" and not in_sq and i + 1 < L and sql[i - 1:i] != ":":
            m = re.match(r":([A-Za-z_][A-Za-z0-9_]*)", sql[i:])
            if m:
                name = m.group(1)
                param_names.append(name)
                out_chars.append("?")
                i += 1 + len(name)
                continue

        out_chars.append(ch)
        i += 1

    sql_qmark = "".join(out_chars)
    values: list = []
    for name in param_names:
        if name not in params:
            raise ValueError(f"Missing SQL parameter: {name}")
        values.append(params[name])
    return sql_qmark, values


def collect_named_params(sql: str) -> list[str]:
    """
    Collect named bind params from SQL, ignoring tokens inside single-quoted literals
    and skipping :: casts. Returns unique names in first-seen order.
    """
    names: list[str] = []
    seen = set()
    i = 0
    L = len(sql)
    in_sq = False
    while i < L:
        ch = sql[i]
        if ch == "'":
            in_sq = not in_sq
            i += 1
            while i < L and in_sq:
                if sql[i] == "'":
                    if i + 1 < L and sql[i + 1] == "'":
                        i += 2
                        continue
                    in_sq = False
                    i += 1
                    break
                i += 1
            continue

        if ch == ":" and not in_sq and i + 1 < L and sql[i - 1:i] != ":":
            m = re.match(r":([A-Za-z_][A-Za-z0-9_]*)", sql[i:])
            if m:
                name = m.group(1)
                if name not in seen:
                    names.append(name)
                    seen.add(name)
                i += 1 + len(name)
                continue
        i += 1
    return names


def connect_via_odbc(dsn: str, user: str, password: str):
    if not pyodbc:
        print("You must install the 'pyodbc' package to use --source_odbc", file=sys.stderr)
        sys.exit(1)
    conn_str = f"DSN={dsn};UID={user};PWD={password}"
    return pyodbc.connect(conn_str, autocommit=True)


def connect_via_oracle(tns: str, user: str, password: str):
    if not oracledb:
        print("You must install the 'oracledb' package to use Oracle TNS connections", file=sys.stderr)
        sys.exit(1)
    try:
        return oracledb.connect(user=user, password=password, dsn=tns)
    except Exception as e:
        print(f"Oracle connection failed: {e}", file=sys.stderr)
        raise


def connect_via_connector(account: str, user: str, password: str, warehouse: str, role: str, database: str, schema: str):
    if not snowflake:
        print("You must install the 'snowflake-connector-python' package", file=sys.stderr)
        sys.exit(1)
    return snowflake.connector.connect(
        user=user,
        password=password,
        account=account,
        warehouse=warehouse,
        role=role,
        database=database,
        schema=schema,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Universal refdata extract runner.")
    parser.add_argument(
        "snow_user",
        nargs="?",
        default=os.getenv("SNOW_USER") or os.getenv("SNOWFLAKE_USER") or "MFG_PRD_RPT_EXENSIO_USER",
        help="Snowflake user (default from $SNOW_USER/$SNOWFLAKE_USER)",
    )
    parser.add_argument(
        "snow_password",
        nargs="?",
        default=os.getenv("SNOW_PASSWORD") or os.getenv("SNOW_PASS") or os.getenv("SNOWFLAKE_PASSWORD") or "",
        help="Snowflake password (default from $SNOW_PASSWORD/$SNOWFLAKE_PASSWORD)",
    )
    parser.add_argument(
        "snow_sid",
        nargs="?",
        default=os.getenv("SNOW_SID") or os.getenv("SNOWFLAKE_DSN") or "MART_SNOWFLAKE",
        help="Snowflake connection identifier (default from $SNOW_SID/$SNOWFLAKE_DSN)",
    )
    parser.add_argument("--account", help="Snowflake account override")
    parser.add_argument("--source_odbc", help="ODBC/DSN style name (uses ODBC when set)")
    parser.add_argument("--source_warehouse", help="Warehouse override")
    parser.add_argument("--source_schema", help="Database and schema DATABASE.SCHEMA")
    parser.add_argument("--warehouse", default="application_prd_wh", help="Snowflake warehouse")
    parser.add_argument("--role", default="APPLICATIONPRD_MFG_CONSUMER_RO", help="Snowflake role")
    parser.add_argument("--secondary_roles", default="ALL", help="Snowflake secondary roles")
    parser.add_argument("--sql_file", help="Path to SQL file with :param placeholders")
    parser.add_argument("--params_json", help="JSON object of SQL parameters")
    parser.add_argument("--params_file", help="Path to JSON file with SQL parameters")
    parser.add_argument(
        "--sources_file",
        help="Path to JSON file with an array of source objects to run in one invocation",
    )
    parser.add_argument(
        "--sources_json",
        help="JSON array of source objects to run in one invocation",
    )
    parser.add_argument("--reference_data_dir", default=os.getenv("REFERENCE_DATA_DIR", ""), help="Output directory")
    parser.add_argument("--archive_dir", default="/apps/exensio_data/archives-yms/reference_data/product", help="Archive directory (gz)")
    parser.add_argument("--log_dir", default="./log", help="Log directory")
    parser.add_argument("--log_file", default="refdata_extract.log", help="Log filename")
    parser.add_argument("--log_level", default="INFO", help="Log level")
    parser.add_argument("--benchmark_log_dir", default="./benchmark", help="Benchmark JSONL log dir")
    parser.add_argument("--benchmark_db_dsn", help="Oracle DSN for benchmark persistence (optional)")
    parser.add_argument("--benchmark_db_user", nargs="?", const="", help="Oracle user for benchmark (default: refdb if flag present)")
    parser.add_argument("--benchmark_db_pass", help="Oracle password for benchmark (optional)")
    parser.add_argument("--output_prefix", default="RefdataExtract", help="Output file prefix")
    parser.add_argument("--pipeline_name", default=SCRIPT_NAME, help="Pipeline name")
    parser.add_argument("--pipeline_type", default="batch", help="Pipeline type")
    # accept dashed form as an alias for compatibility with existing CLI usage
    parser.add_argument("--pipeline-type", dest="pipeline_type", help=argparse.SUPPRESS)
    parser.add_argument("--environment", help="Environment override (prod/dev/test)")
    parser.add_argument("--header", help="Optional header line to write as first row")
    parser.add_argument("--oracle_tns", help="Oracle TNS name or connection string (optional)")
    parser.add_argument("--oracle_user", help="Oracle user (optional)")
    parser.add_argument("--oracle_password", help="Oracle password (optional)")
    parser.add_argument("--column_collapse", help="JSON dict for column fallback/collapse: {output_col: [col_indices]}")
    parser.add_argument("--delimiter", default="|", help="Output field delimiter (default: |)")
    parser.add_argument("--pipeline-name", dest="pipeline_name", help=argparse.SUPPRESS)
    return parser.parse_args()


def resolve_password(raw_password: str) -> str:
    if raw_password == "DW_PASSWORD":
        return os.getenv("DW_PASS") or os.getenv("YMS_PASSWORD") or os.getenv("DW_PASSWORD") or ""
    return raw_password


def sanitize_component(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("_")


def load_sources(args: argparse.Namespace) -> list[dict]:
    if args.sources_file and args.sources_json:
        raise ValueError("Use only one of --sources_file or --sources_json")

    sources_data = None
    if args.sources_file:
        file_ext = os.path.splitext(args.sources_file)[1].lower()
        with open(args.sources_file, "r", encoding="utf-8") as f:
            if file_ext in {".yaml", ".yml"}:
                if not yaml:
                    raise ValueError("PyYAML is required to read .yaml/.yml sources files")
                sources_data = yaml.safe_load(f)
            else:
                sources_data = json.load(f)
    elif args.sources_json:
        sources_data = json.loads(args.sources_json)

    if sources_data is None:
        if not args.sql_file:
            raise ValueError("--sql_file is required when no sources are provided")
        return [
            {
                "name": "default",
                "snow_user": args.snow_user,
                "snow_password": args.snow_password,
                "snow_sid": args.snow_sid,
                "account": args.account,
                "source_odbc": args.source_odbc,
                "source_warehouse": args.source_warehouse,
                "source_schema": args.source_schema,
                "warehouse": args.warehouse,
                "role": args.role,
                "secondary_roles": args.secondary_roles,
                "reference_data_dir": args.reference_data_dir,
                "archive_dir": args.archive_dir,
                "output_prefix": args.output_prefix,
                "params": {},
                "outputs": [
                    {
                        "name": "default",
                        "sql_file": args.sql_file,
                        "output_prefix": args.output_prefix,
                        "reference_data_dir": args.reference_data_dir,
                        "archive_dir": args.archive_dir,
                        "header": args.header,
                        "params": {},
                        "explicit_output_prefix": True,
                    }
                ],
                "explicit_output_prefix": True,
            }
        ]

    if isinstance(sources_data, dict) and "sources" in sources_data:
        sources_data = sources_data["sources"]

    if not isinstance(sources_data, list):
        raise ValueError("sources must be a JSON array or an object with a 'sources' array")

    sources = []
    for source in sources_data:
        if not isinstance(source, dict):
            raise ValueError("Each source entry must be an object")
        source_name = source.get("name")
        explicit_output_prefix = "output_prefix" in source
        outputs = []
        outputs_data = source.get("outputs")
        if outputs_data is None:
            outputs_data = [
                {
                    "name": "default",
                    "sql_file": source.get("sql_file", args.sql_file),
                    "output_prefix": source.get("output_prefix", args.output_prefix),
                    "reference_data_dir": source.get("reference_data_dir", args.reference_data_dir),
                    "archive_dir": source.get("archive_dir", args.archive_dir),
                    "header": source.get("header", args.header),
                    "params": source.get("params", {}),
                    "explicit_output_prefix": explicit_output_prefix,
                }
            ]
        if not isinstance(outputs_data, list):
            raise ValueError("Each source 'outputs' entry must be a list")

        for output in outputs_data:
            if not isinstance(output, dict):
                raise ValueError("Each output entry must be an object")
            output_explicit_prefix = "output_prefix" in output
            outputs.append(
                {
                    "name": output.get("name", "default"),
                    "sql_file": output.get("sql_file", source.get("sql_file", args.sql_file)),
                    "output_prefix": output.get("output_prefix", source.get("output_prefix", args.output_prefix)),
                    "reference_data_dir": output.get("reference_data_dir", source.get("reference_data_dir", args.reference_data_dir)),
                    "archive_dir": output.get("archive_dir", source.get("archive_dir", args.archive_dir)),
                    "header": output.get("header", source.get("header", args.header)),
                    "params": output.get("params", {}),
                    "explicit_output_prefix": output_explicit_prefix or explicit_output_prefix,
                }
            )

        for output in outputs:
            if not output.get("sql_file"):
                raise ValueError("Each output must define sql_file or provide --sql_file")

        sources.append(
            {
                "name": source_name,
                "snow_user": source.get("snow_user", args.snow_user),
                "snow_password": source.get("snow_password", args.snow_password),
                "snow_sid": source.get("snow_sid", args.snow_sid),
                "account": source.get("account", args.account),
                "source_odbc": source.get("source_odbc", args.source_odbc),
                "source_warehouse": source.get("source_warehouse", args.source_warehouse),
                "source_schema": source.get("source_schema", args.source_schema),
                "warehouse": source.get("warehouse", args.warehouse),
                "role": source.get("role", args.role),
                "secondary_roles": source.get("secondary_roles", args.secondary_roles),
                "reference_data_dir": source.get("reference_data_dir", args.reference_data_dir),
                "archive_dir": source.get("archive_dir", args.archive_dir),
                "output_prefix": source.get("output_prefix", args.output_prefix),
                "params": source.get("params", {}),
                "outputs": outputs,
                "explicit_output_prefix": explicit_output_prefix,
            }
        )
    return sources


def write_results(output_path, cursor, write_header=True, header_line: str | None = None,
                  column_collapse: dict | None = None, delimiter: str = "|"):
    """
    Write query results to file.
    Supports single-column legacy mode and multi-column output with optional collapse rules.
    """
    tmp_path = output_path + ".tmp"
    rowcount = 0
    header_cols = [c.strip() for c in header_line.split(delimiter)] if header_line else []
    collapse_keys_upper = {str(k).upper() for k in (column_collapse or {}).keys()}
    desc_names = [str(d[0]).strip() for d in (cursor.description or [])]
    desc_index = {name.upper(): i for i, name in enumerate(desc_names)}
    with open(tmp_path, "w", encoding="utf-8", buffering=1) as outf:
        if write_header and header_line:
            outf.write(header_line.rstrip("\n") + "\n")
        for rows in iter(lambda: cursor.fetchmany(cursor.arraysize), []):
            for row in rows:
                # Single column legacy behavior
                if len(row) == 1 and not column_collapse:
                    value = "" if row[0] is None else str(row[0])
                    value = value.replace("'", "").replace('"', "")
                    outf.write(f"{value}\n")
                    rowcount += 1
                else:
                    if column_collapse:
                        # If header is provided, emit all header columns and only apply collapse
                        # rules to mapped columns (e.g. PRODUCT). Otherwise keep legacy collapse-only output.
                        if header_cols:
                            out_fields = []
                            for col_name in header_cols:
                                key = col_name.upper()
                                val = ""
                                if key in collapse_keys_upper:
                                    # find matching collapse rule regardless of key case
                                    rule_key = next(k for k in column_collapse.keys() if str(k).upper() == key)
                                    for idx in column_collapse.get(rule_key, []):
                                        if isinstance(idx, int) and idx < len(row) and row[idx] is not None:
                                            val = str(row[idx])
                                            break
                                elif key in desc_index:
                                    i = desc_index[key]
                                    v = row[i] if i < len(row) else None
                                    val = "" if v is None else str(v)
                                out_fields.append(val.replace("'", "").replace('"', ""))
                            line = delimiter.join(out_fields)
                        else:
                            out_fields = []
                            for out_col, fallbacks in column_collapse.items():
                                val = ""
                                for idx in fallbacks:
                                    if isinstance(idx, int) and idx < len(row) and row[idx] is not None:
                                        val = str(row[idx])
                                        break
                                out_fields.append(val)
                            line = delimiter.join(out_fields)
                    else:
                        fields = [("" if v is None else str(v)).replace("'", "").replace('"', "") for v in row]
                        line = delimiter.join(fields)
                    outf.write(f"{line}\n")
                    rowcount += 1
    os.replace(tmp_path, output_path)
    return rowcount


def main():
    setup_early_logging()

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
            "Pipeline: %s | Type: %s | Environment: %s | Script: %s",
            pipeline_info["pipeline_name"],
            pipeline_info["pipeline_type"],
            pipeline_info["environment"],
            SCRIPT_NAME,
        )

        for d in [args.reference_data_dir, args.benchmark_log_dir, args.log_dir]:
            if not d:
                logging.error("Directory argument is empty: %s", d)
                print(f"Directory argument is empty: {d}", file=sys.stderr)
                sys.exit(1)
            os.makedirs(d, exist_ok=True)

        date_code = datetime.now().strftime("%Y%m%d_%H%M%S")

        if not args.source_odbc and not args.account:
            args.source_odbc = (
                os.getenv("SOURCE_ODBC")
                or os.getenv("SNOWFLAKE_DSN")
                or os.getenv("SNOW_SID")
                or args.snow_sid
            )

        base_params = parse_params(args.params_json, args.params_file)
        sources = load_sources(args)
        multi_source = len(sources) > 1

        for source in sources:
            source_name = source.get("name") or source.get("source_odbc") or source.get("account") or "source"
            safe_source_name = sanitize_component(str(source_name)) or "source"
            if not source["source_odbc"] and not source["account"]:
                source["source_odbc"] = (
                    os.getenv("SOURCE_ODBC")
                    or os.getenv("SNOWFLAKE_DSN")
                    or os.getenv("SNOW_SID")
                    or source["snow_sid"]
                )

            for output in source["outputs"]:
                output_name = output.get("name", "output")
                safe_output_name = sanitize_component(str(output_name)) or "output"
                output_prefix = output["output_prefix"]
                if multi_source and not output["explicit_output_prefix"]:
                    output_prefix = f"{output_prefix}-{safe_source_name}"
                elif output_name != "default" and not output["explicit_output_prefix"]:
                    output_prefix = f"{output_prefix}-{safe_output_name}"

                out_file = os.path.join(
                    output["reference_data_dir"], f"{output_prefix}-{date_code}.prod"
                )

                sql_query = read_sql_file(output["sql_file"])
                params = dict(base_params)
                if source.get("params"):
                    params.update(source["params"])
                # Ensure optional date params exist so SQL can bind NULL and use fallback window
                params.setdefault("from_date", None)
                params.setdefault("to_date", None)
                if output.get("params"):
                    params.update(output["params"])
                sql_exec, sql_params = (
                    prepare_sql_with_params(sql_query, params) if ":" in sql_query else (sql_query, [])
                )

                start_time = time.time()
                start_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                start_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

                logging.info("Running export for %s/%s to %s ...", source_name, output_name, out_file)

                conn = None
                rowcount = 0
                try:
                    if not source["snow_user"] or not source["snow_sid"]:
                        logging.error("Missing Snowflake user or DSN/account.")
                        print("Missing Snowflake user or DSN/account.", file=sys.stderr)
                        sys.exit(1)

                    password = resolve_password(source["snow_password"])
                    if not password:
                        logging.error("Password resolution failed for DW_PASSWORD.")
                        print("Password resolution failed for DW_PASSWORD.", file=sys.stderr)
                        sys.exit(1)
                    account = (
                        source["account"]
                        or source["source_odbc"]
                        or os.getenv("SNOWFLAKE_ACCOUNT")
                        or source["snow_sid"]
                    )
                    database = None
                    schema = None
                    if source["source_schema"]:
                        if "." in source["source_schema"]:
                            database, schema = source["source_schema"].split(".", 1)
                        else:
                            schema = source["source_schema"]

                    # Determine connection type: ODBC, Oracle (LOTG/override), or Snowflake connector
                    is_oracle = False
                    oracle_tns = None
                    # Per-source indicator: if source_odbc is the special LOTGDB marker, treat as Oracle
                    if source.get("source_odbc") and str(source.get("source_odbc")).upper().startswith("LOTG"):
                        is_oracle = True
                        oracle_tns = source.get("oracle_tns") or args.oracle_tns or source.get("snow_sid") or args.snow_sid
                    # CLI-level SID indicating LOTGPRD or similar
                    elif args.snow_sid and "LOTG" in str(args.snow_sid).upper():
                        is_oracle = True
                        oracle_tns = args.oracle_tns or args.snow_sid

                    collapse_config = None
                    if output.get("column_collapse") or args.column_collapse:
                        collapse_json = output.get("column_collapse") or args.column_collapse
                        collapse_config = json.loads(collapse_json) if isinstance(collapse_json, str) else collapse_json

                    if source.get("source_odbc") and not is_oracle:
                        conn = connect_via_odbc(source["source_odbc"], source["snow_user"], password)
                        cur = conn.cursor()
                        if source["source_warehouse"]:
                            cur.execute(f"use warehouse {source['source_warehouse']}")
                        if source["source_schema"]:
                            cur.execute(f"use schema {source['source_schema']}")
                        if source["secondary_roles"]:
                            cur.execute(f"use secondary roles {source['secondary_roles']}")
                        if sql_params:
                            cur.execute(sql_exec, sql_params)
                        else:
                            cur.execute(sql_exec)
                        if cur.description is None:
                            logging.error("The executed statement returned no result set.")
                            print("The executed statement returned no result set.", file=sys.stderr)
                            sys.exit(2)
                        cur.arraysize = 10000
                        rowcount = write_results(
                            out_file,
                            cur,
                            write_header=True,
                            header_line=output.get("header") or args.header,
                            column_collapse=collapse_config,
                            delimiter=output.get("delimiter") or args.delimiter,
                        )
                        cur.close()
                    elif is_oracle and oracle_tns:
                        # Oracle connection
                        # Handle LOTGDB_USER special-case similar to get_subcon_lot_refdata_rc10.py
                        u = source.get("snow_user") or args.snow_user
                        p = source.get("snow_password") or args.snow_password
                        if u == "LOTGDB_USER":
                            oracle_user = "LOTG_READ"
                            oracle_pwd = os.getenv("LOTG_PASS") or "prdlotgr"
                        else:
                            oracle_user = source.get("oracle_user") or args.oracle_user or u
                            oracle_pwd = source.get("oracle_password") or args.oracle_password or p
                        conn = connect_via_oracle(oracle_tns, oracle_user, oracle_pwd)
                        cur = conn.cursor()
                        # Oracle uses named binds, not qmark positional binds.
                        oracle_sql = sql_query.strip()
                        # Script files often end with ';' or '/' (SQL*Plus style), which oracledb
                        # treats as invalid SQL text and can raise ORA-00933.
                        oracle_sql = re.sub(r"[\s;]+$", "", oracle_sql)
                        if oracle_sql.endswith("/"):
                            oracle_sql = oracle_sql[:-1].rstrip()

                        oracle_bind_names = collect_named_params(oracle_sql)
                        if oracle_bind_names:
                            oracle_params = {k: params.get(k) for k in oracle_bind_names}
                            cur.execute(oracle_sql, oracle_params)
                        else:
                            cur.execute(oracle_sql)
                        if cur.description is None:
                            logging.error("The executed statement returned no result set.")
                            print("The executed statement returned no result set.", file=sys.stderr)
                            sys.exit(2)
                        cur.arraysize = 10000
                        rowcount = write_results(
                            out_file,
                            cur,
                            write_header=True,
                            header_line=output.get("header") or args.header,
                            column_collapse=collapse_config,
                            delimiter=output.get("delimiter") or args.delimiter,
                        )
                        cur.close()
                    else:
                        conn = connect_via_connector(
                            account=account,
                            user=source["snow_user"],
                            password=password,
                            warehouse=source["source_warehouse"] or source["warehouse"],
                            role=source["role"],
                            database=database,
                            schema=schema,
                        )
                        with conn.cursor() as cur:
                            if source["source_warehouse"]:
                                cur.execute(f"use warehouse {source['source_warehouse']};")
                            if source["source_schema"]:
                                cur.execute(f"use schema {source['source_schema']};")
                            if source["secondary_roles"]:
                                cur.execute(f"use secondary roles {source['secondary_roles']};")
                            if sql_params:
                                cur.execute(sql_exec, sql_params)
                            else:
                                cur.execute(sql_exec)
                            if cur.description is None:
                                logging.error("The executed statement returned no result set.")
                                print("The executed statement returned no result set.", file=sys.stderr)
                                sys.exit(2)
                            cur.arraysize = 10000
                            rowcount = write_results(
                                out_file,
                                cur,
                                write_header=True,
                                header_line=output.get("header") or args.header,
                                column_collapse=collapse_config,
                                delimiter=output.get("delimiter") or args.delimiter,
                            )
                except Exception as e:
                    logging.error("Error during export: %s", e)
                    sys.exit(2)
                finally:
                    if conn:
                        try:
                            conn.close()
                        except Exception:
                            pass

                elapsed = time.time() - start_time
                end_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                end_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                human_elapsed = format_elapsed(elapsed)
                archived_file = "NA"

                if os.path.exists(out_file) and rowcount > 0:
                    logging.info("Export succeeded: %s (%s rows)", out_file, rowcount)
                    logging.info("Elapsed time: %s (%.3f seconds)", human_elapsed, elapsed)
                    if output["archive_dir"]:
                        archived_path = archive_and_compress(out_file, output["archive_dir"])
                        if archived_path:
                            archived_file = archived_path
                else:
                    logging.error("Export failed or produced empty file.")
                    sys.exit(2)

                stats = {
                    "start_local": start_local,
                    "end_local": end_local,
                    "start_utc": start_utc,
                    "end_utc": end_utc,
                    "elapsed_seconds": round(elapsed, 3),
                    "elapsed_human": human_elapsed,
                    "output_file": os.path.abspath(out_file),
                    "rowcount": rowcount,
                    # Align with models.py: rows_extracted = rows from source, rows_written = rows to output
                    "rows_extracted": rowcount,
                    "rows_written": rowcount,
                    "total_files": 1,  # Single output file per refdata_extract run
                    "log_file": os.path.join(args.log_dir, args.log_file),
                    "archived_file": archived_file if archived_file != "NA" else None,
                    "pid": os.getpid(),
                    "date_code": date_code,
                    "pipeline_name": pipeline_info["pipeline_name"],
                    "script_name": pipeline_info["script_name"],
                    "pipeline_type": pipeline_info["pipeline_type"],
                    "environment": pipeline_info["environment"],
                    # Optional metadata fields for future extensibility
                    "source_name": source_name,
                    "output_name": output_name,
                }
                log_benchmark_jsonl(args.benchmark_log_dir, stats)
                
                # Write to Oracle DB if credentials provided
                if args.benchmark_db_dsn:
                    # Handle the nargs='?' pattern: if --benchmark_db_user is present but empty, use defaults
                    oracle_user = args.benchmark_db_user if args.benchmark_db_user is not None else None
                    oracle_pass = args.benchmark_db_pass
                    log_benchmark_to_oracle(stats, args.benchmark_db_dsn, oracle_user, oracle_pass)

        logging.info("Benchmark log appended to %s/benchmark.jsonl", args.benchmark_log_dir)
        logging.info("----- Job finished -----")
    finally:
        pass


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.critical("Uncaught error: %s", e, exc_info=True)
        print(f"Script failed: {e}", file=sys.stderr)
        sys.exit(3)
