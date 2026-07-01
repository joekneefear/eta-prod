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
import platform

try:
    import snowflake.connector  # pip install snowflake-connector-python
except ImportError:
    snowflake = None

try:
    import pyodbc  # pip install pyodbc
except ImportError:
    pyodbc = None

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
    # Explicit hostname mapping (mirrors Perl scripts):
    # usaz15ls082 => prod, usaz15ls080 => qa, usaz15ls081 => dev
    detected_env = "prod"
    if "usaz15ls082" in hostname:
        detected_env = "prod"
    elif "usaz15ls080" in hostname:
        detected_env = "qa"
    elif "usaz15ls081" in hostname:
        detected_env = "dev"
    elif re.search(r"dev|test|uat|stage", hostname):
        detected_env = "dev" if "dev" in hostname else "test"
    environment = os.getenv("PIPELINE_ENV", detected_env)
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


class SingleInstance:
    def __init__(self, lock_file: str) -> None:
        self.lock_file = lock_file
        self._fh = None

    def __enter__(self) -> "SingleInstance":
        os.makedirs(os.path.dirname(self.lock_file), exist_ok=True)
        self._fh = open(self.lock_file, "a+", encoding="utf-8")
        try:
            if platform.system().lower().startswith("win"):
                import msvcrt

                msvcrt.locking(self._fh.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(self._fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except Exception as exc:
            raise RuntimeError(f"Another instance is already running: {self.lock_file}") from exc
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        if not self._fh:
            return
        try:
            if platform.system().lower().startswith("win"):
                import msvcrt

                self._fh.seek(0)
                msvcrt.locking(self._fh.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(self._fh, fcntl.LOCK_UN)
        finally:
            try:
                self._fh.close()
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
    param_names = []

    def repl(match: re.Match) -> str:
        name = match.group(1)
        param_names.append(name)
        return "?"

    sql_qmark = re.sub(r"(?<!:):([A-Za-z_][A-Za-z0-9_]*)", repl, sql)
    values = []
    for name in param_names:
        if name not in params:
            raise ValueError(f"Missing SQL parameter: {name}")
        values.append(params[name])
    return sql_qmark, values


def connect_via_odbc(dsn: str, user: str, password: str):
    if not pyodbc:
        print("You must install the 'pyodbc' package to use --source_odbc", file=sys.stderr)
        sys.exit(1)
    conn_str = f"DSN={dsn};UID={user};PWD={password}"
    return pyodbc.connect(conn_str, autocommit=True)


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
    parser.add_argument("--output_prefix", default="RefdataExtract", help="Output file prefix")
    parser.add_argument("--pipeline_name", default=SCRIPT_NAME, help="Pipeline name")
    parser.add_argument("--pipeline_type", default="batch", help="Pipeline type")
    parser.add_argument("--environment", help="Environment override (prod/dev/test)")
    parser.add_argument("--header", help="Optional header line to write as first row")
    parser.add_argument("--column_collapse", help="JSON dict for column fallback/collapse: {output_col: [col_indices]}")
    parser.add_argument("--delimiter", default="|", help="Output field delimiter (default: |)")
    parser.add_argument("--lock_file", help="Explicit lock file path (defaults to ./log/{pipeline_name}.lock)")
    parser.add_argument("--disable_lock", action="store_true", help="Disable singleton lock")
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
    
    Args:
        output_path: Output file path
        cursor: Database cursor with result set
        write_header: Whether to write header line
        header_line: Header line to write (pipe-delimited or custom delimiter)
        column_collapse: Dict mapping output_col -> [fallback_cols] for COALESCE-like behavior
                        e.g., {"PRODUCT": ["PARENT_PRODUCT", "PRODUCT"]}
        delimiter: Field delimiter (default: "|")
    """
    tmp_path = output_path + ".tmp"
    rowcount = 0
    with open(tmp_path, "w", encoding="utf-8", buffering=1) as outf:
        if write_header and header_line:
            outf.write(header_line.rstrip("\n") + "\n")
        for rows in iter(lambda: cursor.fetchmany(cursor.arraysize), []):
            for row in rows:
                # Single column mode (legacy, no collapse)
                if len(row) == 1 and not column_collapse:
                    value = "" if row[0] is None else str(row[0])
                    value = value.replace("'", "").replace('"', "")
                    outf.write(f"{value}\n")
                    rowcount += 1
                # Multi-column mode (with optional collapse)
                else:
                    if column_collapse:
                        # Build output based on collapse rules
                        row_dict = {f"col{i}": row[i] for i in range(len(row))}
                        output_fields = []
                        for output_col, fallback_cols in column_collapse.items():
                            # Find first non-None value from fallback chain
                            value = ""
                            for col_idx in fallback_cols:
                                if isinstance(col_idx, int) and col_idx < len(row):
                                    if row[col_idx] is not None:
                                        value = str(row[col_idx])
                                        break
                            output_fields.append(value)
                        line = delimiter.join(output_fields)
                    else:
                        # No collapse: output all columns as-is
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

        # Singleton Lock Implementation
        if args.disable_lock:
            lock_ctx = None
        else:
            lock_file = args.lock_file
            if not lock_file:
                # Dynamic lock name based on pipeline_name
                safe_pipeline = sanitize_component(pipeline_info["pipeline_name"])
                lock_file = f"./log/{safe_pipeline}.lock"
            lock_ctx = SingleInstance(lock_file)

        if lock_ctx:
            lock_ctx.__enter__()

        try:
            _execute_main(args, pipeline_info)
        finally:
            if lock_ctx:
                lock_ctx.__exit__(None, None, None)

    finally:
        pass


def _execute_main(args, pipeline_info):
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
            # Ensure from_date/to_date keys exist so the SQL can bind NULLs when absent
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

                if source["source_odbc"]:
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
                    collapse_config = None
                    if output.get("column_collapse") or args.column_collapse:
                        collapse_json = output.get("column_collapse") or args.column_collapse
                        collapse_config = json.loads(collapse_json) if isinstance(collapse_json, str) else collapse_json
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
                        collapse_config = None
                        if output.get("column_collapse") or args.column_collapse:
                            collapse_json = output.get("column_collapse") or args.column_collapse
                            collapse_config = json.loads(collapse_json) if isinstance(collapse_json, str) else collapse_json
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
                # Per-output benchmark fields (pipeline-service model additions)
                "rows_extracted": rowcount,
                "rows_written": rowcount,
                "total_files": 1,
                "out_files": [{"path": os.path.abspath(out_file), "rows": rowcount}],
                "log_file": os.path.join(args.log_dir, args.log_file),
                "archived_file": archived_file,
                "pid": os.getpid(),
                "date_code": date_code,
                "pipeline_name": pipeline_info["pipeline_name"],
                "script_name": pipeline_info["script_name"],
                "pipeline_type": pipeline_info["pipeline_type"],
                "environment": pipeline_info["environment"],
                "source_name": source_name,
                "output_name": output_name,
            }
            log_benchmark_jsonl(args.benchmark_log_dir, stats)

    logging.info("Benchmark log appended to %s/benchmark.jsonl", args.benchmark_log_dir)
    logging.info("----- Job finished -----")



if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logging.critical("Uncaught error: %s", e, exc_info=True)
        print(f"Script failed: {e}", file=sys.stderr)
        sys.exit(3)
