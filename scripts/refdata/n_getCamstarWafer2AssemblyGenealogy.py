#!/usr/bin/env python3
"""
Python port of n_getCamstarWafer2AssemblyGenealogy.pl

Core features:
- Camstar MSSQL consumption extract
- refdb WS + LOTG fallback for source lot/fab resolution
- DW/Snowflake SITE_DIM lookup for fab descriptions
- Genealogy + Trace output generation
- Robust logging + benchmark JSONL
- Singleton lock
"""

from __future__ import annotations

import argparse
import gzip
import json
import logging
import logging.handlers
import os
import platform
import re
import shutil
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Optional, Tuple

try:
    import pyodbc  # pip install pyodbc
except ImportError:
    pyodbc = None

try:
    import oracledb  # pip install oracledb
except ImportError:
    oracledb = None

try:
    import requests  # pip install requests
except ImportError:
    requests = None

try:
    import urllib.request as urllib_request
except Exception:
    urllib_request = None

SCRIPT_PATH = Path(__file__).resolve()
SCRIPT_NAME = SCRIPT_PATH.name

ON_LOT_WS_URL = "http://globmfgapp.onsemi.com:61050/exensioreftables-ws/api/onlot/bylotid/"
PP_LOT_PROD_WS_URL = "http://globmfgapp.onsemi.com:61050/exensioreftables-ws/api/pplotprod/bylotid/"

CLASS50_HEADER = (
    "LOT|ASSEMBLY_PART_COUNT|SOURCE_LOT|LOT_TYPE|PRODUCT|CONSUMPTION_DATE|FROM_PRODUCT|"
    "FROM_EXENSIO_SOURCE_LOT|FROM_EXENSIO_WAFER_ID|FROM_WAFER_NUMBER|FROM_FAB|"
    "FROM_INVENTORY_LOT|FROM_WAFER_SCRIBE|QTY_CONSUMED|QTY_REQUIRED|CONSUME_FACTOR|"
    "MATERIAL_LOT|ASSEMBLY_STEP"
)

FAIRCHILD_FABS = {"KRG": 1, "KRI": 2, "KRH": 3, "KRJ": 4, "UWA": 5, "CBA": 6, "PBC": 7, "UWB": 8}


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


def format_elapsed(elapsed_sec: float) -> str:
    mins, sec = divmod(int(elapsed_sec), 60)
    hrs, mins = divmod(mins, 60)
    result = []
    if hrs:
        result.append(f"{hrs}h")
    if mins:
        result.append(f"{mins}m")
    result.append(f"{sec}s")
    return " ".join(result)


def get_pipeline_info() -> Dict[str, str]:
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


def archive_and_compress(file_path: str, archive_dir: str) -> Optional[str]:
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


@dataclass
class CamstarSource:
    dsn: str
    user: str
    password: str


CAMSTAR_SOURCES: Dict[str, CamstarSource] = {
    "CEBU": CamstarSource("MSSQL-Perl", "ymsapp_rd", "yms20150"),
    "OSV": CamstarSource("MSSQL-OSV", "READ_ONLY_REPORTS", "Cosine9#3!SC"),
    "SBN": CamstarSource("MSSQL-SBN", "read_only_rptusrs", "rptusrs"),
    "OSPI": CamstarSource("MSSQL-OSPI", "read_only_rptusrs", "rptusrs"),
    "ONSC": CamstarSource("MSSQL-ONSC", "READ_ONLY_REPORTS", "Sqrt9#3!SC"),
    "ONSZ": CamstarSource("MSSQL-Suzhou", "ymsapp_ro", "yms20150"),
}


def resolve_camstar_source(source_db: str) -> CamstarSource:
    if source_db not in CAMSTAR_SOURCES:
        raise ValueError(f"SOURCE_DB must be one of: {' '.join(CAMSTAR_SOURCES.keys())}")
    source = CAMSTAR_SOURCES[source_db]
    # Allow overrides via env
    user = os.getenv(f"CAMSTAR_{source_db}_USER", source.user)
    password = os.getenv(f"CAMSTAR_{source_db}_PASS", source.password)
    return CamstarSource(source.dsn, user, password)


def connect_odbc(dsn: str, user: str, password: str):
    if not pyodbc:
        raise RuntimeError("pyodbc is required for ODBC connections")
    conn_str = f"DSN={dsn};UID={user};PWD={password}"
    return pyodbc.connect(conn_str, autocommit=True)


def prepare_sql_with_params(sql: str, params: dict) -> Tuple[str, List[Any]]:
    param_names: List[str] = []

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


def read_sql_file(sql_path: Path) -> str:
    with sql_path.open("r", encoding="utf-8") as f:
        return f.read()


def iter_rows(cursor) -> Iterator[Dict[str, Any]]:
    columns = [col[0] for col in cursor.description]
    for rows in iter(lambda: cursor.fetchmany(cursor.arraysize), []):
        for row in rows:
            yield {col: row[idx] for idx, col in enumerate(columns)}


def get_sql_file_for_source(source_db: str, sql_dir: Path) -> Path:
    if source_db in {"ONSZ", "CEBU"}:
        return sql_dir / "camstar_wafer_consume_activity_cebu_onsz.sql"
    if source_db in {"SBN", "OSPI"}:
        return sql_dir / "camstar_wafer_consume_activity_sbn_ospi.sql"
    return sql_dir / "camstar_wafer_consume_activity_default.sql"


def get_fab_codes(source_warehouse: str, source_schema: str) -> Dict[str, str]:
    snow_user = os.getenv("SNOW_USER", os.getenv("SNOWFLAKE_USER", ""))
    snow_pass = os.getenv("SNOW_PASS", os.getenv("SNOWFLAKE_PASSWORD", ""))
    snow_dsn = os.getenv("SNOW_SID", os.getenv("SNOWFLAKE_DSN", "MART_SNOWFLAKE"))
    if not snow_user or not snow_pass:
        raise RuntimeError("SNOW_USER/SNOW_PASS must be set for Snowflake lookup")
    db = ""
    if source_schema and "." in source_schema:
        db = source_schema.split(".", 1)[0] + ".ENTERPRISE"
    if not db:
        raise RuntimeError("SOURCE_SCHEMA must include a database (DATABASE.SCHEMA)")

    conn = connect_odbc(snow_dsn, snow_user, snow_pass)
    try:
        cur = conn.cursor()
        if source_warehouse:
            cur.execute(f"use warehouse {source_warehouse}")
        cur.execute(f"use database {db}")
        sql = (
            "SELECT DISTINCT sd.mfg_area_code AS MFG_AREA_CD, "
            "sd.mfg_area_description AS MFG_AREA_DESC "
            "FROM enterprise.site_dim sd "
            "WHERE mfg_area_code != 'N/A' "
            "AND mfg_area_code IS NOT NULL "
            "ORDER BY mfg_area_code"
        )
        cur.execute(sql)
        fab_codes: Dict[str, str] = {}
        for row in cur.fetchall():
            fab_codes[row[0]] = row[1]
        return fab_codes
    finally:
        conn.close()


def safe_str(value: Any) -> str:
    return "" if value is None else str(value)


def fetch_json(url: str, timeout_sec: int = 30) -> Dict[str, Any]:
    if requests:
        resp = requests.get(url, timeout=timeout_sec)
        resp.raise_for_status()
        return resp.json() if resp.content else {}
    if not urllib_request:
        raise RuntimeError("No HTTP client available (install requests)")
    with urllib_request.urlopen(url, timeout=timeout_sec) as resp:
        data = resp.read().decode("utf-8")
        return json.loads(data) if data else {}


def get_meta_from_refdb_ws(url: str) -> Dict[str, Any]:
    try:
        data = fetch_json(url)
    except Exception as exc:
        logging.warning("WS call failed: %s (%s)", url, exc)
        return {"status": "error", "sourceLot": "", "fab": ""}

    if not isinstance(data, dict):
        return {"status": "error", "sourceLot": "", "fab": ""}
    status = data.get("status") or data.get("STATUS") or ""
    source_lot = data.get("sourceLot") or data.get("SOURCE_LOT") or data.get("source_lot") or ""
    fab = data.get("fab") or data.get("FAB") or ""
    return {"status": status, "sourceLot": source_lot, "fab": fab}


def check_source_lot(source_lot: str, fab_id: str) -> str:
    new_source = source_lot
    if re.match(r"^USR.*", fab_id) and len(source_lot) > 8:
        new_source = source_lot[:8]
    elif re.match(r"^UV5.*", fab_id) and re.match(r".+\.0\d\d$", source_lot) and len(source_lot) > 5:
        new_source = source_lot[:-4]
    elif (re.match(r"^CZ4.*", fab_id) or fab_id in {"ISMFAB", "LFOUNDRY"}) and len(source_lot) > 7:
        new_source = source_lot[:7]
    elif re.match(r"^JND.*", fab_id) and re.match(r"^.+0\d$", source_lot) and len(source_lot) > 8:
        new_source = source_lot[:8]
    elif re.match(r"^(KRI|KRH|KRG).*", fab_id) and len(source_lot) > 8:
        new_source = source_lot[:8]
    elif re.match(r"^USU.*", fab_id) and len(source_lot) > 6:
        new_source = source_lot[:6]
    elif re.match(r"^TWQ.*", fab_id) and len(source_lot) > 5:
        new_source = source_lot[:5]
    return new_source


def check_assembly_source_lot(assembly_lot: str, assembly_source_lot: str, fab_source_lot: str, fab_id: str) -> str:
    candidate = check_source_lot(assembly_source_lot[:-2], fab_id) + ".S"
    if candidate == fab_source_lot and assembly_source_lot != fab_source_lot:
        logging.info("Changing assembly source lot \"%s\" to \"%s\"", assembly_source_lot, candidate)
        return candidate
    return assembly_source_lot


def get_umr_scribe(source_lot: str, wafer_num: str, material_lot_id: str) -> Optional[str]:
    if not oracledb:
        logging.warning("oracledb not installed; cannot query UMR")
        return None
    umr_pass = os.getenv("UMR_PASS", "")
    if not umr_pass:
        logging.warning("UMR_PASS is not set")
        return None

    sql = (
        "SELECT LASERSCRIBE FROM ("
        "SELECT UNIQUE LASERSCRIBE, "
        "DENSE_RANK() OVER (PARTITION BY MES_LOT_ID, WAFER_NUMBER ORDER BY CREATED_TIME DESC) AS DR "
        "FROM UMR.UMR_WAFER_MAP_MD_VALUES "
        "WHERE MES_LOT_ID like :lot_prefix AND CAST(WAFER_NUMBER as INTEGER) = :wafer_num"
        ") WHERE DR=1"
    )

    conn = oracledb.connect(user="umr_ro", password=umr_pass, dsn="UMRPRD")
    try:
        cur = conn.cursor()
        lot_prefix = f"{source_lot}.00%"
        cur.execute(sql, lot_prefix=lot_prefix, wafer_num=int(wafer_num))
        row = cur.fetchone()
        if not row:
            logging.warning("Failed to find UV5/EFK scribe in UMR for %s %s wafer %s", material_lot_id, source_lot, wafer_num)
            return None
        return row[0]
    finally:
        conn.close()


def check_wafer_id(
    source_lot: str,
    wafer_num: str,
    wafer_scribe: str,
    fab_id: str,
    material_lot_id: str,
    scribe_cache: Dict[str, Dict[str, str]],
) -> Tuple[str, str]:
    wafer_id = ""
    if fab_id in FAIRCHILD_FABS:
        wafer_id = f"{source_lot}_{wafer_num}"
    else:
        if fab_id in {"USR", "UV5", "JND", ""}:
            if fab_id == "UV5" and re.search(r"\s", wafer_scribe or ""):
                cached = scribe_cache.get(source_lot, {}).get(wafer_num)
                if cached:
                    wafer_id = cached
                    wafer_scribe = cached
                    logging.info(
                        "Material lot ID %s consumes invalid UV5/EFK scribe ID \"%s\". Replacing with cached scribe %s",
                        material_lot_id,
                        wafer_scribe,
                        cached,
                    )
                else:
                    scribe = get_umr_scribe(source_lot, wafer_num, material_lot_id)
                    if not scribe:
                        wafer_id = ""
                    else:
                        wafer_id = scribe
                        wafer_scribe = scribe
                        scribe_cache.setdefault(source_lot, {})[wafer_num] = scribe
                        logging.warning(
                            "Material lot ID %s consumes invalid UV5/EFK scribe ID \"%s\". Replacing with scribe %s",
                            material_lot_id,
                            wafer_scribe,
                            scribe,
                        )
            else:
                wafer_id = wafer_scribe
        elif fab_id in {"CZ4", "USU", "BE2"} or fab_id.startswith("ISMF"):
            wafer_id = f"{source_lot}-W{wafer_num}"
        else:
            wafer_id = f"{source_lot}-{wafer_num}"

    return wafer_id, wafer_scribe


def lotg_lookup(lotid: str) -> Dict[str, str]:
    if not oracledb:
        logging.warning("oracledb not installed; cannot query LOTG")
        return {}
    lotg_pass = os.getenv("LOTG_PASS", "")
    if not lotg_pass:
        logging.warning("LOTG_PASS is not set")
        return {}

    sql = LOTG_SQL
    conn = oracledb.connect(user="LOTG_READ", password=lotg_pass, dsn="LOTGPRD")
    try:
        cur = conn.cursor()
        cur.execute(sql, lotid=lotid)
        result = {}
        for row in cur:
            result["SOURCE_LOT"] = row[0]
            result["FAB"] = row[1]
        return result
    finally:
        conn.close()


def format_qty(value: Any) -> str:
    if value is None:
        return ""
    try:
        return f"{int(round(float(value)))}"
    except Exception:
        return str(value)


def ensure_tmp_dir(base_dir: str) -> str:
    tmp_dir = os.path.join(base_dir, "tmp")
    os.makedirs(tmp_dir, exist_ok=True)
    return tmp_dir


def gzip_file(src_path: str) -> str:
    gz_path = src_path + ".gz"
    with open(src_path, "rb") as f_in, gzip.open(gz_path, "wb") as f_out:
        shutil.copyfileobj(f_in, f_out)
    os.remove(src_path)
    return gz_path


def process_camstar(
    source_db: str,
    start_hours: int,
    end_hours: int,
    out_gen: str,
    archive_gen: str,
    out_trace: str,
    archive_trace: str,
    source_warehouse: str,
    source_schema: str,
) -> Tuple[int, int, int]:
    camstar = resolve_camstar_source(source_db)
    fab_codes = get_fab_codes(source_warehouse, source_schema)

    sql_dir = SCRIPT_PATH.parent / "sql"
    sql_path = get_sql_file_for_source(source_db, sql_dir)
    sql_text = read_sql_file(sql_path)
    sql_exec, sql_params = prepare_sql_with_params(sql_text, {"start_hours": start_hours, "end_hours": end_hours})

    conn = connect_odbc(camstar.dsn, camstar.user, camstar.password)
    try:
        cur = conn.cursor()
        cur.execute(sql_exec, sql_params)
        cur.arraysize = 5000

        is_fmr_fairchild = source_db in {"ONSZ", "CEBU"}

        gen_info: Dict[str, str] = {}
        trace_info: Dict[str, str] = {}
        source_lots: Dict[str, str] = {}
        source_fabs: Dict[str, str] = {}
        scribe_ids: Dict[str, Dict[str, str]] = {}
        onlot_cache: Dict[str, Dict[str, Any]] = {}
        pplot_cache: Dict[str, Dict[str, Any]] = {}
        lotg_cache: Dict[str, Dict[str, str]] = {}

        for ref in iter_rows(cur):
            assembly_source_lot = ""
            fab_source_lot = ""
            fab_id = ""
            from_fab = ""

            assembly_part_count = format_qty(ref.get("AssemblyQty"))
            fab_part_count = format_qty(ref.get("QtyConsumed"))
            fab_part_required = format_qty(ref.get("QtyRequired"))
            consume_factor = format_qty(ref.get("ConsumeFactor"))

            wafer_scribe = ref.get("FromWaferScribeNumber", "") or ""
            logging.info(
                "AssemblyLot: %s, FromWaferScribe: %s, Qty: %s",
                ref.get("AssemblyLot"),
                wafer_scribe,
                fab_part_count,
            )

            assembly_lot = safe_str(ref.get("AssemblyLot"))
            material_lot_id = safe_str(ref.get("MaterialLotID"))
            material_lot_fab = safe_str(ref.get("MaterialLotFab"))
            from_wafer_number = safe_str(ref.get("FromWaferNumber"))

            if assembly_lot in source_lots:
                assembly_source_lot = source_lots[assembly_lot] + ".S"
            elif is_fmr_fairchild or source_db == "ONSC":
                assembly_source_lot = f"{assembly_lot}.S"
                source_lots[assembly_lot] = assembly_lot
            else:
                ws_call = ON_LOT_WS_URL + str(assembly_lot)
                on_lot = onlot_cache.get(assembly_lot)
                if on_lot is None:
                    on_lot = get_meta_from_refdb_ws(ws_call)
                    onlot_cache[assembly_lot] = on_lot

                if re.search(r"no_data|error", on_lot.get("status", ""), re.I) or not on_lot.get("sourceLot"):
                    lotg = lotg_cache.get(assembly_lot)
                    if lotg is None:
                        lotg = lotg_lookup(str(assembly_lot))
                        lotg_cache[assembly_lot] = lotg
                    if not lotg.get("SOURCE_LOT"):
                        logging.warning(
                            "ON_LOT WS asm call for %s returned no results and LOTG lookup failed (%s).",
                            assembly_lot,
                            ws_call,
                        )
                        fab_returned = (material_lot_fab.split(":", 1)[0] if material_lot_fab else "")
                        assembly_source_lot = check_source_lot(material_lot_id, fab_returned) + ".S"
                    else:
                        fab_returned = lotg.get("FAB", "")
                        assembly_source_lot = check_source_lot(lotg.get("SOURCE_LOT", ""), fab_returned) + ".S"
                else:
                    fab_returned = on_lot.get("fab", "").split(":", 1)[0]
                    if fab_returned in {"JPF", "SG1"}:
                        lotg = lotg_cache.get(assembly_lot)
                        if lotg is None:
                            lotg = lotg_lookup(str(assembly_lot))
                            lotg_cache[assembly_lot] = lotg
                        if lotg.get("FAB") == "CZ4:TESLA FAB":
                            logging.warning("Incorrect source fab JPF, should be CZ4. Substituting source lot %s", lotg.get("SOURCE_LOT"))
                            assembly_source_lot = check_source_lot(lotg.get("SOURCE_LOT", ""), lotg.get("FAB", "")) + ".S"
                        elif lotg.get("FAB") and fab_returned == "SG1":
                            fab_returned = lotg.get("FAB")
                            assembly_source_lot = check_source_lot(lotg.get("SOURCE_LOT", ""), fab_returned) + ".S"
                        else:
                            assembly_source_lot = check_source_lot(on_lot.get("sourceLot", ""), fab_returned) + ".S"
                    else:
                        assembly_source_lot = check_source_lot(on_lot.get("sourceLot", ""), fab_returned) + ".S"

                if fab_returned in FAIRCHILD_FABS or f"{assembly_lot}.S" == assembly_source_lot:
                    source_lots[assembly_lot] = "GET"
                else:
                    source_lots[assembly_lot] = assembly_source_lot[:-2]

            # Suzhou fix
            if source_db == "ONSZ" and material_lot_fab == material_lot_id:
                lotg = lotg_cache.get(material_lot_id)
                if lotg is None:
                    lotg = lotg_lookup(str(material_lot_id))
                    lotg_cache[material_lot_id] = lotg
                if lotg.get("FAB") and lotg.get("FAB") != material_lot_fab:
                    new_fab = lotg.get("FAB").split(":", 1)[0]
                    logging.warning("Incorrect source fab from Camstar \"%s\". Changing to \"%s\"", material_lot_fab, new_fab)
                    material_lot_fab = new_fab
                elif not lotg.get("FAB"):
                    logging.warning("Failed to find source fab for material lot \"%s\"", material_lot_id)
                    material_lot_fab = ""

            exensio_wafer_id = ""

            if material_lot_id in source_lots:
                fab_source_lot = source_lots[material_lot_id]
                fab_id = source_fabs.get(material_lot_id, "")
                exensio_wafer_id, wafer_scribe = check_wafer_id(
                    fab_source_lot, from_wafer_number, wafer_scribe, fab_id, material_lot_id, scribe_ids
                )
                fab_source_lot += ".S"
                assembly_source_lot = check_assembly_source_lot(assembly_lot, assembly_source_lot, fab_source_lot, fab_id)
            elif material_lot_fab in FAIRCHILD_FABS:
                ws_call = PP_LOT_PROD_WS_URL + str(material_lot_id)
                pp_lot = pplot_cache.get(material_lot_id)
                if pp_lot is None:
                    pp_lot = get_meta_from_refdb_ws(ws_call)
                    pplot_cache[material_lot_id] = pp_lot
                if re.search(r"no_data|error", pp_lot.get("status", ""), re.I) or pp_lot.get("fab") == "KRG" or (
                    pp_lot.get("fab") == "UWB" and not re.match(r"^M.*$", pp_lot.get("sourceLot", ""))
                ):
                    lotg = lotg_cache.get(material_lot_id)
                    if lotg is None:
                        lotg = lotg_lookup(str(material_lot_id))
                        lotg_cache[material_lot_id] = lotg
                    if lotg.get("SOURCE_LOT") and lotg.get("SOURCE_LOT") != pp_lot.get("sourceLot"):
                        fab_source_lot = check_source_lot(lotg.get("SOURCE_LOT", ""), material_lot_fab)
                        logging.warning(
                            "Incorrect source lot \"%s\" for pp_lot \"%s\". Substituting source lot \"%s\"",
                            pp_lot.get("sourceLot"),
                            material_lot_id,
                            fab_source_lot,
                        )
                        source_lots[material_lot_id] = fab_source_lot
                        source_fabs[material_lot_id] = material_lot_fab
                        exensio_wafer_id, wafer_scribe = check_wafer_id(
                            fab_source_lot, from_wafer_number, wafer_scribe, material_lot_fab, material_lot_id, scribe_ids
                        )
                        fab_source_lot += ".S"
                    elif pp_lot.get("sourceLot") and pp_lot.get("sourceLot") != "N/A":
                        fab_source_lot = check_source_lot(pp_lot.get("sourceLot", ""), material_lot_fab)
                        source_lots[material_lot_id] = fab_source_lot
                        source_fabs[material_lot_id] = material_lot_fab
                        exensio_wafer_id, wafer_scribe = check_wafer_id(
                            fab_source_lot, from_wafer_number, wafer_scribe, material_lot_fab, material_lot_id, scribe_ids
                        )
                        fab_source_lot += ".S"
                    else:
                        if len(str(material_lot_id)) > 8 and material_lot_fab in {"KRH", "KRG"}:
                            trunc_lot = str(material_lot_id)[:8]
                            ws_call = PP_LOT_PROD_WS_URL + trunc_lot
                            pp_lot2 = get_meta_from_refdb_ws(ws_call)
                            if re.search(r"no_data|error", pp_lot2.get("status", ""), re.I):
                                logging.warning(
                                    "Source lot not found for lot \"%s\", fab \"%s\". Using %s as source lot",
                                    trunc_lot,
                                    material_lot_fab,
                                    trunc_lot,
                                )
                                fab_source_lot = trunc_lot + ".S"
                                source_lots[trunc_lot] = pp_lot2.get("sourceLot", "")
                                source_fabs[trunc_lot] = material_lot_fab
                                exensio_wafer_id, wafer_scribe = check_wafer_id(
                                    trunc_lot, from_wafer_number, wafer_scribe, material_lot_fab, material_lot_id, scribe_ids
                                )
                            else:
                                fab_source_lot = pp_lot2.get("sourceLot", "") + ".S"
                                source_lots[trunc_lot] = pp_lot2.get("sourceLot", "")
                                source_fabs[trunc_lot] = material_lot_fab
                                exensio_wafer_id, wafer_scribe = check_wafer_id(
                                    pp_lot2.get("sourceLot", ""), from_wafer_number, wafer_scribe, material_lot_fab, material_lot_id, scribe_ids
                                )
                        else:
                            logging.warning(
                                "Source lot not found for lot \"%s\". Using material lot for source lot",
                                material_lot_id,
                            )
                            fab_source_lot = str(material_lot_id) + ".S"
                            source_lots[material_lot_id] = str(material_lot_id)
                            source_fabs[material_lot_id] = material_lot_fab
                            exensio_wafer_id, wafer_scribe = check_wafer_id(
                                str(material_lot_id), from_wafer_number, wafer_scribe, material_lot_fab, material_lot_id, scribe_ids
                            )
                else:
                    fab_source_lot = check_source_lot(pp_lot.get("sourceLot", ""), material_lot_fab)
                    exensio_wafer_id, wafer_scribe = check_wafer_id(
                        fab_source_lot, from_wafer_number, wafer_scribe, material_lot_fab, material_lot_id, scribe_ids
                    )
                    if material_lot_fab != pp_lot.get("fab"):
                        logging.warning("MaterialLotFab \"%s\" doesn't match PP_PROD fab \"%s\".", material_lot_fab, pp_lot.get("fab"))
                    source_lots[material_lot_id] = fab_source_lot
                    source_fabs[material_lot_id] = material_lot_fab
                    fab_source_lot += ".S"
            else:
                ws_call = ON_LOT_WS_URL + str(material_lot_id)
                on_lot = onlot_cache.get(material_lot_id)
                if on_lot is None:
                    on_lot = get_meta_from_refdb_ws(ws_call)
                    onlot_cache[material_lot_id] = on_lot
                if re.search(r"no_data|error", on_lot.get("status", ""), re.I) or not on_lot.get("sourceLot"):
                    logging.warning("ON_LOT WS call for %s returned no results (%s), checking LOTG", material_lot_id, ws_call)
                    lotg = lotg_cache.get(material_lot_id)
                    if lotg is None:
                        lotg = lotg_lookup(str(material_lot_id))
                        lotg_cache[material_lot_id] = lotg
                    if lotg.get("SOURCE_LOT"):
                        fab_source_lot = check_source_lot(lotg.get("SOURCE_LOT", ""), lotg.get("FAB", ""))
                        if not material_lot_fab and lotg.get("FAB"):
                            fab_id = lotg.get("FAB").split(":", 1)[0]
                            logging.info("Camstar material lot \"%s\" fab not defined, substituting \"%s\" from ON_LOT", material_lot_id, fab_id)
                            material_lot_fab = fab_id
                    else:
                        logging.warning("LOTG lookup for \"%s\" returned no results. Using \"%s\" for source lot", material_lot_id, material_lot_id)
                        fab_source_lot = check_source_lot(str(material_lot_id), material_lot_fab)
                elif on_lot.get("fab") in {"SBN", "ISMFAB", "UMC"} or material_lot_fab == "LFOUNDRY":
                    if material_lot_fab == "LFOUNDRY" and on_lot.get("fab") == "UVA":
                        fab_id = material_lot_fab
                    else:
                        fab_id = (on_lot.get("fab") or "").split(":", 1)[0]
                    lotg = lotg_cache.get(material_lot_id)
                    if lotg is None:
                        lotg = lotg_lookup(str(material_lot_id))
                        lotg_cache[material_lot_id] = lotg
                    if lotg.get("SOURCE_LOT") and lotg.get("SOURCE_LOT") != on_lot.get("sourceLot"):
                        logging.warning(
                            "Incorrect source lot \"%s\" for lot \"%s\". Substituting source lot \"%s\"",
                            on_lot.get("sourceLot"),
                            material_lot_id,
                            lotg.get("SOURCE_LOT"),
                        )
                        fab_id = (lotg.get("FAB") or "").split(":", 1)[0]
                        fab_source_lot = check_source_lot(lotg.get("SOURCE_LOT", ""), fab_id)
                    else:
                        fab_source_lot = check_source_lot(on_lot.get("sourceLot", ""), fab_id)
                else:
                    fab_source_lot = on_lot.get("sourceLot", "")
                    if not material_lot_fab and on_lot.get("fab"):
                        material_lot_fab = on_lot.get("fab")
                    elif material_lot_fab and material_lot_fab != on_lot.get("fab"):
                        logging.warning(
                            "MaterialLotFab \"%s\" doesn't match ON_LOT fab \"%s\" for lot \"%s\" + wafer \"%s\".",
                            material_lot_fab,
                            on_lot.get("fab"),
                            assembly_lot,
                            wafer_scribe,
                        )

                fab_source_lot = fab_source_lot.replace(".S", "")
                old_src = fab_source_lot
                fab_source_lot = check_source_lot(fab_source_lot, material_lot_fab)
                exensio_wafer_id, wafer_scribe = check_wafer_id(
                    fab_source_lot, from_wafer_number, wafer_scribe, material_lot_fab, material_lot_id, scribe_ids
                )
                source_lots[material_lot_id] = fab_source_lot
                if not fab_id:
                    source_fabs[material_lot_id] = material_lot_fab
                else:
                    source_fabs[material_lot_id] = fab_id
                fab_source_lot += ".S"
                assembly_source_lot = check_assembly_source_lot(assembly_lot, assembly_source_lot, fab_source_lot, material_lot_fab)

            if source_lots.get(assembly_lot) == "GET":
                assembly_source_lot = source_lots.get(material_lot_id, "") + ".S"
                source_lots[assembly_lot] = assembly_source_lot[:-2]

            if not fab_id:
                fab_id = material_lot_fab

            if fab_id in fab_codes:
                from_fab = f"{fab_id}:{fab_codes[fab_id]}"
            else:
                logging.warning("Fab code \"%s\" not found in DWPRD", fab_id)
                from_fab = material_lot_fab or "NA"

            gen_event_name = f"{assembly_lot}_{safe_str(ref.get('SpecName'))}_{fab_source_lot}"
            stripped_dt = safe_str(ref.get("txnDate"))
            stripped_dt = re.sub(r"[: -]", "", stripped_dt)
            trace_event_name = f"{assembly_lot}:{fab_source_lot}:{exensio_wafer_id}:{stripped_dt}"

            if gen_event_name in gen_info:
                gen_line = gen_info[gen_event_name]
            else:
                gen_line = (
                    f"AWGEN|{safe_str(ref.get('SpecName'))}|{safe_str(ref.get('txnDate'))}|{gen_event_name}|"
                    f"{assembly_source_lot}|{assembly_lot}|{safe_str(ref.get('LotType'))}|{safe_str(ref.get('ProductName'))}|"
                    f"{assembly_part_count}|{from_fab}|{safe_str(ref.get('MaterialPartName'))}|{fab_source_lot}|{material_lot_id}"
                )

            gen_line = f"{gen_line}|{exensio_wafer_id}|{from_wafer_number}"
            trace_line = (
                f"{assembly_lot}|{assembly_part_count}|{assembly_source_lot}|{safe_str(ref.get('LotType'))}|{safe_str(ref.get('ProductName'))}|"
                f"{safe_str(ref.get('txnDate'))}|{safe_str(ref.get('MaterialPartName'))}|{fab_source_lot}|{exensio_wafer_id}|"
                f"{from_wafer_number}|{from_fab}|{material_lot_id}|{wafer_scribe}|{fab_part_count}|"
                f"{fab_part_required}|{consume_factor}|{safe_str(ref.get('MaterialLotName'))}|{safe_str(ref.get('SpecName'))}"
            )

            if exensio_wafer_id and fab_source_lot and fab_source_lot != ".S":
                gen_info[gen_event_name] = gen_line
                trace_info[trace_event_name] = trace_line
            else:
                logging.warning(
                    "Consumption record will not be written for assembly lot %s. Invalid wafer scribe %s",
                    assembly_lot,
                    ref.get("FromWaferScribeNumber"),
                )

        logging.info("DONE. Writing out Results.")
    finally:
        conn.close()

    tmp_gen = ensure_tmp_dir(out_gen)
    tmp_trace = ensure_tmp_dir(out_trace)

    current_dt = datetime.now().strftime("%Y%m%d_%H%M%S")
    gen_file = f"Assembly2Wafer.{source_db}.{current_dt}.a2wgen"

    gen_path = os.path.join(tmp_gen, gen_file)
    with open(gen_path, "w", encoding="utf-8") as out_f:
        for k in sorted(gen_info.keys()):
            out_f.write(gen_info[k] + "\n")

    gz_gen = gzip_file(gen_path)
    shutil.copy(gz_gen, os.path.join(archive_gen, os.path.basename(gz_gen)))
    shutil.move(gz_gen, os.path.join(out_gen, os.path.basename(gz_gen)))

    trace_files: List[str] = []
    for k in sorted(trace_info.keys()):
        assembly_lot, fab_source_lot, exensio_wafer_id, dt = k.split(":")
        trace_lot_file = f"Assembly2Wafer.{source_db}.{current_dt}.{assembly_lot}.{dt}.a2w.csv"
        trace_path = os.path.join(tmp_trace, trace_lot_file)
        if not os.path.exists(trace_path):
            with open(trace_path, "w", encoding="utf-8") as out_f:
                out_f.write(CLASS50_HEADER + "\n")
            trace_files.append(trace_lot_file)
        with open(trace_path, "a", encoding="utf-8") as out_f:
            out_f.write(trace_info[k] + "\n")

        fab_source_lot = fab_source_lot[:-2]
        trace_lot_file = f"Wafer2Assembly.{source_db}.{current_dt}.{fab_source_lot}.{dt}.w2a.csv"
        trace_path = os.path.join(tmp_trace, trace_lot_file)
        if not os.path.exists(trace_path):
            with open(trace_path, "w", encoding="utf-8") as out_f:
                out_f.write(CLASS50_HEADER + "\n")
            trace_files.append(trace_lot_file)
        with open(trace_path, "a", encoding="utf-8") as out_f:
            out_f.write(trace_info[k] + "\n")

    for file_name in trace_files:
        source_file = os.path.join(tmp_trace, file_name)
        gz_path = gzip_file(source_file)
        shutil.copy(gz_path, os.path.join(archive_trace, os.path.basename(gz_path)))
        shutil.move(gz_path, os.path.join(out_trace, os.path.basename(gz_path)))

    return len(gen_info), len(trace_info), len(trace_files)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Camstar Wafer2Assembly Genealogy Extract (Python)")
    parser.add_argument("--source_db", required=True, help="Camstar source DB (CEBU/OSV/SBN/OSPI/ONSC/ONSZ)")
    parser.add_argument("--source_warehouse", required=True, help="Snowflake warehouse")
    parser.add_argument("--source_schema", required=True, help="Snowflake database.schema")
    parser.add_argument("--start_hours", type=int, default=2, help="Start hours back")
    parser.add_argument("--end_hours", type=int, default=0, help="End hours back")
    parser.add_argument("--out_gen", required=True, help="Genealogy output directory")
    parser.add_argument("--archive_gen", required=True, help="Genealogy archive directory")
    parser.add_argument("--out_trace", required=True, help="Trace output directory")
    parser.add_argument("--archive_trace", required=True, help="Trace archive directory")
    parser.add_argument("--log_dir", default="./log", help="Log directory")
    parser.add_argument("--log_file", default="n_getCamstarWafer2AssemblyGenealogy.log", help="Log filename")
    parser.add_argument("--logfile", help="Legacy log filename (alias for --log_file)")
    parser.add_argument("--log_level", default="INFO", help="Log level")
    parser.add_argument("--benchmark_log_dir", default="./benchmark", help="Benchmark JSONL log dir")
    parser.add_argument("--lock_file", default="./log/n_getCamstarWafer2AssemblyGenealogy.lock", help="Lock file path")
    parser.add_argument("--disable_lock", action="store_true", help="Disable singleton lock")
    return parser.parse_args()


def validate_dirs(*dirs: str) -> None:
    for d in dirs:
        if not d:
            raise ValueError("Directory argument is empty")
        os.makedirs(d, exist_ok=True)


def main() -> None:
    args = parse_args()
    if args.logfile:
        args.log_file = args.logfile
    setup_logging(args.log_dir, args.log_file, args.log_level)

    validate_dirs(args.out_gen, args.archive_gen, args.out_trace, args.archive_trace, args.benchmark_log_dir)

    pipeline_info = get_pipeline_info()

    start_time = time.time()
    start_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    start_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    if args.disable_lock:
        lock_ctx = None
    else:
        lock_ctx = SingleInstance(args.lock_file)

    try:
        if lock_ctx:
            lock_ctx.__enter__()

        gen_rows, trace_rows, trace_files = process_camstar(
            source_db=args.source_db,
            start_hours=args.start_hours,
            end_hours=args.end_hours,
            out_gen=args.out_gen,
            archive_gen=args.archive_gen,
            out_trace=args.out_trace,
            archive_trace=args.archive_trace,
            source_warehouse=args.source_warehouse,
            source_schema=args.source_schema,
        )
    finally:
        if lock_ctx:
            lock_ctx.__exit__(None, None, None)

    elapsed = time.time() - start_time
    end_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    end_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    human_elapsed = format_elapsed(elapsed)

    stats = {
        "start_local": start_local,
        "end_local": end_local,
        "start_utc": start_utc,
        "end_utc": end_utc,
        "elapsed_seconds": round(elapsed, 3),
        "elapsed_human": human_elapsed,
        "rowcount": gen_rows + trace_rows,
        "gen_rows": gen_rows,
        "trace_rows": trace_rows,
        "trace_files": trace_files,
        "log_file": os.path.join(args.log_dir, args.log_file),
        "pipeline_name": pipeline_info["pipeline_name"],
        "script_name": pipeline_info["script_name"],
        "pipeline_type": pipeline_info["pipeline_type"],
        "environment": pipeline_info["environment"],
        "source_db": args.source_db,
    }
    log_benchmark_jsonl(args.benchmark_log_dir, stats)
    logging.info("----- Job finished -----")


LOTG_SQL = r"""
WITH src_tgt_xref_with as
(
SELECT /* +INLINE */
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
, to_char((cast(FK1GENEALOGY_MANOD as TIMESTAMP) + (TO_TIMESTAMP(substr(FK1GENEALOGY_MANOT,1,4),'HH24MI')-trunc(TO_TIMESTAMP(substr(FK1GENEALOGY_MANOT,1,4),'HH24MI'))+(cast(substr(FK1GENEALOGY_MANOT, 5, 4) as real)/100)*interval '1'second)), 'YYYY-MM-DD HH24:MI:SS.FF' ) as TRANS_DT
, to_char((cast(FK_GENEALOGY_MANOD as TIMESTAMP) + (TO_TIMESTAMP(substr(FK_GENEALOGY_MANOT,1,4),'HH24MI')-trunc(TO_TIMESTAMP(substr(FK_GENEALOGY_MANOT,1,4),'HH24MI'))+(cast(substr(FK_GENEALOGY_MANOT, 5, 4) as real)/100)*interval '1'second)), 'YYYY-MM-DD HH24:MI:SS.FF') as PARENT_TRANS_DT
, (POST_DATE + (TO_TIMESTAMP(substr(POST_TIME,1,4),'HH24MI')-trunc(TO_TIMESTAMP(substr(POST_TIME,1,4),'HH24MI'))+(cast(substr(POST_TIME, 5, 4) as real)/100)*interval '1'second)) as POST_DT
  FROM LOTG_OWNER.SRC_TGT_XREF
)
, min_trans_date_lots as
(
SELECT *
FROM (
SELECT mt.*
, DENSE_RANK() OVER (PARTITION BY LOT_NUM ORDER BY case when ppi.PART_TYPE in ('Wafer Fab Part') then 1
                                                   when ppi.PART_TYPE in ('Wafer Post Fab Part') then 2
                                                   when ppi.PART_TYPE in ('WDQ Part') then 3
                                                   when ppi.PART_TYPE in ('Assembly Part') then 4
                                                   else 5 end, TRANSDATE, TRANSTIME) as LOT_RANK
FROM src_tgt_xref_with mt
LEFT JOIN LOTG_OWNER.PC_ITEM pi on mt.PART_ID = pi.PART_ID
LEFT JOIN LOTG_OWNER.PC_ITEM ppi on mt.PARENT_PART_ID = ppi.PART_ID
WHERE pi.PART_TYPE not in ('Substrate Part', 'Ingot Part')
and mt.TRANSDATE > sysdate - 10*interval '1' year
AND NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = mt.LOT_NUM and vx.PARENT_LOT_NUM != mt.PARENT_LOT_NUM
                        and vx.TRANSDATE = mt.TRANSDATE and vx.TRANSTIME = mt.TRANSTIME and vx.PART_ID = mt.PART_ID and vx.PARENT_PART_ID = mt.PARENT_PART_ID)
) tgt
WHERE tgt.LOT_RANK = 1
)
, starting_lots as
(
SELECT LOT_NUM, LOT_CLASS, PART_ID
, PARENT_LOT_NUM
, PARENT_PART_ID, v.PARENT_LOT_CLASS, TRANSDATE, TRANSTIME
FROM min_trans_date_lots v
WHERE lot_num in (:lotid)
AND NOT ( LOT_NUM = PARENT_LOT_NUM AND PART_ID = PARENT_PART_ID
          AND NOT EXISTS (SELECT 1 from src_tgt_xref_with sl
                          LEFT JOIN LOTG_OWNER.PC_ITEM pi on sl.PARENT_PART_ID = pi.PART_ID
                          WHERE v.LOT_NUM = sl.LOT_NUM and v.PART_ID = SL.PART_ID
                            AND pi.PART_TYPE not in ('Substrate Part', 'Ingot Part')
                            AND sl.PARENT_LOT_CLASS NOT IN (SELECT LOTCLASS_CD FROM LOTG_OWNER.LOT_CLASS WHERE DESCRIPTION like '%ORION%')
                            AND NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = sl.LOT_NUM and vx.PARENT_LOT_NUM != sl.PARENT_LOT_NUM
                                           and vx.TRANSDATE = sl.TRANSDATE and vx.TRANSTIME = sl.TRANSTIME and vx.PART_ID = sl.PART_ID and vx.PARENT_PART_ID = sl.PARENT_PART_ID)
                         )
        )
AND NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = v.LOT_NUM and vx.PARENT_LOT_NUM != v.PARENT_LOT_NUM
                        and vx.TRANSDATE = v.TRANSDATE and vx.TRANSTIME = v.TRANSTIME and vx.PART_ID = v.PART_ID and vx.PARENT_PART_ID = v.PARENT_PART_ID)
AND v.LOT_RANK = 1
)
, starting_lots_ranked as
(
select s.*, dense_rank() over (order by case when regexp_like(lot_num, '^.+\.\d$') then 1
                                             when exists(select 1 from starting_lots s2 where regexp_like(s2.lot_num, '..'||s.lot_num)) then 4
                                             when exists(select 1 from starting_lots s2 where length(s2.lot_num) > length(s.lot_num)) then 3
                                             else 2 end) as sl_dr
from starting_lots s
)
, walk as
(
SELECT /*+ MATERIALIZE */ UNIQUE w.*, ppi.PART_TYPE as PARENT_PART_TYPE
FROM (
SELECT LOT_NUM, LOT_CLASS, PART_ID
, PARENT_LOT_NUM, PARENT_LOT_CLASS, PARENT_PART_ID
, TRANSDATE, TRANSTIME
, TRANS_DT, PARENT_TRANS_DT, LEVEL as LVL
, dense_rank() over (partition by LOT_NUM, PART_ID ORDER BY TO_DATE(substr(PRIOR TRANS_DT, 1, 18), 'YYYY-MM-DD HH24:MI:SS') - TO_DATE(substr(PARENT_TRANS_DT, 1, 18), 'YYYY-MM-DD HH24:MI:SS')) as RNK
FROM (
SELECT v.LOT_NUM, v.LOT_CLASS, v.PART_ID
     , v.PARENT_LOT_NUM as LOTG_PARENT_LOT_NUM
     , COALESCE(t.ORIGINATOR, v.PARENT_LOT_NUM) as PARENT_LOT_NUM
     , v.PARENT_LOT_CLASS
     , v.PARENT_PART_ID
     , TRANS_DT, PARENT_TRANS_DT
     , TRANSDATE, TRANSTIME
FROM src_tgt_xref_with v
LEFT JOIN LOTG_OWNER.ORN_OUT_ORACLE_TRAK t on v.PARENT_LOT_NUM = t.LOT_ID and v.PARENT_PART_ID = t.TARGET_ITEM and t.TARGET_ITEM not like '%-PBU'
LEFT JOIN LOTG_OWNER.ORN_RECEIPTS r on t.ORIGINATOR = r.LOT_NUM and t.TARGET_ITEM = r.PART
WHERE NOT EXISTS(SELECT 1 from src_tgt_xref_with vx where vx.LOT_NUM = v.LOT_NUM and vx.PARENT_LOT_NUM != v.PARENT_LOT_NUM
                        and vx.TRANSDATE = v.TRANSDATE and vx.TRANSTIME = v.TRANSTIME and vx.PART_ID = v.PART_ID and vx.PARENT_PART_ID = v.PARENT_PART_ID)
) v
CONNECT BY NOCYCLE (PRIOR PARENT_PART_ID = PART_ID or regexp_substr(PRIOR PARENT_PART_ID, '[^-]+[-]*[^-]+', 1) = regexp_substr(PART_ID, '[^-]+[-]*[^-]+', 1))
               AND PRIOR PARENT_LOT_NUM = LOT_NUM
               AND PRIOR PARENT_TRANS_DT >= TRANS_DT
               AND NOT(LOT_NUM=PARENT_LOT_NUM AND PART_ID=PARENT_PART_ID AND LOT_CLASS=PARENT_LOT_CLASS)
START WITH EXISTS(SELECT 1 FROM starting_lots_ranked sl
                  WHERE sl.LOT_NUM = v.LOT_NUM and sl.parent_lot_num = v.LOTG_PARENT_LOT_NUM and sl.TRANSDATE  = v.TRANSDATE and sl.TRANSTIME = v.TRANSTIME and sl.sl_dr = 1
                 )
) w
LEFT JOIN LOTG_OWNER.PC_ITEM ppi on w.PARENT_PART_ID = ppi.PART_ID
WHERE LVL = 1 or ((ppi.PART_TYPE not in ('Substrate Part', 'Ingot Part') and w.PARENT_PART_ID not like '%-BAS'))
)
, translate as (
SELECT UNIQUE
       w.LOT_NUM as LOT
     , w.LOT_CLASS
     , w.LOT_CLASS as LOT_OWNER
     , w.PART_ID   as PRODUCT
     , COALESCE(cbt.TYPE, 'UNK') as PART_TYPE
     , CASE WHEN w.PARENT_PART_TYPE in ('Substrate Part', 'Ingot Part') THEN LOT_NUM ELSE PARENT_LOT_NUM END as PARENT_LOT
     , w.PARENT_LOT_CLASS
     , CASE WHEN w.PARENT_PART_TYPE in ('Substrate Part', 'Ingot Part') THEN PART_ID ELSE PARENT_PART_ID END as PARENT_PRODUCT
     , w.PARENT_PART_TYPE
     , CASE WHEN w.PARENT_PART_TYPE in ('Substrate Part', 'Ingot Part') THEN 'CHILD' ELSE 'PARENT' END as RELATIONSHIP
     , TRANS_DT, PARENT_TRANS_DT
from walk w
left JOIN LOTG_OWNER.LOTG_BOM_TYPE cbt on w.PART_ID = cbt.PART
)
, src_lot_walk as
(SELECT LOT, PRODUCT
, PARENT_LOT
, PARENT_PRODUCT
, RELATIONSHIP
, '' as PARENT_LOT_CLASS
, CONNECT_BY_ROOT LOT as TOP
, RANK() OVER (PARTITION BY CONNECT_BY_ROOT LOT ORDER BY TRANS_DT) AS DR
, regexp_substr(PRIOR PARENT_PRODUCT, '[^-]+[-]*[^-]+', 1) as x1
, regexp_substr(PRODUCT, '[^-]+[-]*[^-]+', 1) as x2
FROM translate w
CONNECT BY NOCYCLE (PRIOR PARENT_PRODUCT = PRODUCT AND PRIOR PARENT_LOT = LOT AND NOT (PRODUCT = PARENT_PRODUCT and LOT = PARENT_LOT) and PRIOR PARENT_TRANS_DT >= TRANS_DT)
START WITH PART_TYPE in ('FG','WFR', 'WAFER', 'DIE','RS','UNK')
)
, src_lot as
(
SELECT UNIQUE TOP AS LOT
, PARENT_LOT_CLASS||PARENT_LOT AS SOURCE_LOT
, PARENT_PRODUCT as SOURCE_PRODUCT
, RELATIONSHIP
FROM src_lot_walk w
WHERE DR = 1
)
, bom_site as
(
SELECT x.*
     , dense_rank() over (PARTITION by START_PART order by RNK, LVL DESC) as bom_rnk
FROM (
SELECT pba.PART_ID, coalesce(pisa.SITE_ID, pba.SITE_ID)||
CASE WHEN coalesce(pisa.SITE_ID, pba.SITE_ID) IS NULL then '' ELSE ':' END||
CASE WHEN coalesce(pisa.SITE_ID, pba.SITE_ID) = 'BE2' then 'BELGAN FE (ARB)'
     WHEN pisa.SITE_DESC IS NULL THEN (SELECT MIN(SITE_DESC) FROM LOTG_OWNER.PC_ITEMSITE pis2 WHERE pba.SITE_ID = pis2.SITE_ID)
ELSE pisa.SITE_DESC END
as SITE_DESC
, CONNECT_BY_ROOT pba.PART_ID as START_PART
, LEVEL as LVL
, rank() OVER (PARTITION BY pba.PART_ID ORDER BY pba.PREFERENCE_CD, pba.ALTERNATE_BILL, pisa.SITE_DESC) as rnk
FROM LOTG_OWNER.PC_BOM pba
LEFT JOIN LOTG_OWNER.PC_ITEMSITE pisa on pba.PART_ID = pisa.PART_ID AND pba.SITE_ID = pisa.SITE_ID
CONNECT BY NOCYCLE PRIOR COMPONENT_PART_ID = pba.PART_ID AND pba.ITEM_TYPE NOT IN ('Substrate Part', 'Ingot Part')
START WITH pba.PART_ID in (select distinct SOURCE_PRODUCT from src_lot)
) x
WHERE x.rnk = 1
)
, fab_info as
(
SELECT x.LOT_NUM as LOT, x.FROM_BANK_CODE, x.rnk
, CASE
  WHEN COALESCE(ornr.VENDOR_NAME, mbs.MFG_AREA_DESC) like '%NON%RECORDING%BANK'
    OR (mbs.MFG_AREA_CD is not null and mbs.MFG_STAGE_CD not in ('FAB','RWF','ADJ','DCY','PP'))
  THEN COALESCE((select unique SITE_DESC FROM bom_site bs WHERE bs.bom_rnk = 1 and bs.START_PART = x.SOURCE_PRODUCT), 'UNKNOWN')
  ELSE COALESCE(ornr.MFG_AREA_CD, mbs.MFG_AREA_CD)||':'||COALESCE(ornr.VENDOR_NAME, mbs.MFG_AREA_DESC) END as FAB_NAME
, COALESCE(mbs.MFG_STAGE_DESC, 'RECEIPT') as FAB_STAGE
, x.SOURCE_PRODUCT
FROM (SELECT sl.SOURCE_LOT as LOT_NUM, PARENT_LOT_CLASS, TRANSDATE, TRANSTIME, t.TRANSACTION_DT, b.FROM_BANK_CODE, SOURCE_PRODUCT
           , RANK() OVER (PARTITION BY sl.SOURCE_LOT ORDER BY TRANSDATE, TRANSTIME, t.TRANSACTION_DT) as RNK
      FROM src_lot sl
      LEFT JOIN src_tgt_xref_with b on ((sl.RELATIONSHIP = 'CHILD' AND sl.SOURCE_LOT = b.LOT_NUM and sl.SOURCE_PRODUCT = b.PART_ID)
                                      or (sl.RELATIONSHIP = 'PARENT' AND sl.SOURCE_LOT = b.PARENT_LOT_NUM and sl.SOURCE_PRODUCT = b.PARENT_PART_ID ))
      LEFT JOIN LOTG_OWNER.ORN_OUT_ORACLE_TRAK t on sl.SOURCE_LOT = t.ORIGINATOR
      JOIN LOTG_OWNER.PC_ITEM i on sl.SOURCE_PRODUCT = i.PART_ID
      WHERE i.PART_TYPE not in ('Substrate Part', 'Ingot Part')
      ) x
LEFT JOIN LOTG_OWNER.MFG_BANK_TO_STAGE mbs on x.FROM_BANK_CODE = mbs.BANK_CD
LEFT JOIN LOTG_OWNER.ORN_RECEIPTS ornr on x.LOT_NUM = ornr.lot_num and x.SOURCE_PRODUCT = ornr.PART
WHERE x.RNK = 1
)
select * from (
SELECT UNIQUE t.LOT
     , t.PARENT_LOT
     , case when regexp_like(t.PRODUCT, '^[^-]+-[^-]+-[^-]+-[^-]+-[^-][^-][^-]$') then regexp_substr(t.PRODUCT, '^[^-]+-[^-]+-[^-]+-[^-]+')
            when regexp_like(t.PRODUCT, '^[^-]+-[^-]+-[^-][^-][^-]$') then regexp_substr(t.PRODUCT, '^[^-]+-[^-]+')
            when regexp_like(t.PRODUCT, '^[^-]+-[^-][^-][^-]$') then regexp_substr(t.PRODUCT, '^[^-]+')
       else t.PRODUCT END as PRODUCT
     , 'NOT AVAILABLE' as LOT_OWNER
     , CASE when regexp_like(t.PARENT_PRODUCT, '^[^-]+-[^-]+-[^-]+-[^-]+-[^-][^-][^-]$') then regexp_substr(t.PARENT_PRODUCT, '^[^-]+-[^-]+-[^-]+-[^-]+')
            WHEN regexp_like(t.PARENT_PRODUCT, '^[^-]+-[^-]+-[^-][^-][^-]$') then regexp_substr(t.PARENT_PRODUCT, '^[^-]+-[^-]+')
            when regexp_like(t.PARENT_PRODUCT, '^[^-]+-[^-][^-][^-]$') then regexp_substr(t.PARENT_PRODUCT, '^[^-]+')
            else t.PARENT_PRODUCT END as PARENT_PRODUCT
     , CASE WHEN f.FAB_NAME like 'UV5:%'
            THEN regexp_replace(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '\\.0\d\d$','',1,1)
            WHEN f.FAB_NAME like 'USR:%'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 8)
            WHEN f.FAB_NAME like 'USU:%'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 6)
            WHEN f.FAB_NAME like 'JND:%' and regexp_like(sl.SOURCE_LOT, '^.+0\d$')
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 8)
            WHEN (f.FAB_NAME like 'MYD:%' or f.FAB_NAME like 'ISMFAB:%') and regexp_like(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '^.+\.[0-9]+[A-Z]$')
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, instr(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '.')-1)
            WHEN f.FAB_NAME like 'CZ4:%' or f.FAB_NAME like 'ISMFAB:%' or f.FAB_NAME like 'UVA:%' or f.FAB_NAME like 'LFOUNDRY:%'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 7)
            WHEN (f.FAB_NAME like 'UMC:%' or f.FAB_NAME like 'MYD:%' ) and regexp_like(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '^.+\.[0-9]+$')
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, instr(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '.')-1)
            WHEN sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT
            ELSE t.PARENT_LOT
       END as SOURCE_LOT
     , CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_PRODUCT ELSE t.PARENT_PRODUCT END as "WAFER_PART/ALTERNATE_PRODUCT"
     , f.FAB_NAME as FAB
     , 'NOT AVAILABLE' as LOT_TYPE
     , t.LOT_CLASS
     , 'NOT AVAILABLE' as MASKSET
     , CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_PRODUCT ELSE t.PARENT_PRODUCT END as "PRODUCT_CODE"
     , dense_rank() over (PARTITION by CASE WHEN f.FAB_NAME like 'UV5:%'
            THEN regexp_replace(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '\\.0\d\d$','',1,1)
            WHEN f.FAB_NAME like 'USR:%'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 8)
            WHEN f.FAB_NAME like 'USU:%'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 6)
            WHEN f.FAB_NAME like 'JND:%' and regexp_like(sl.SOURCE_LOT, '^.+0\d$')
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 8)
            WHEN (f.FAB_NAME like 'MYD:%' or f.FAB_NAME like 'ISMFAB:%') and regexp_like(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '^.+\.[0-9]+[A-Z]$')
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, instr(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '.')-1)
            WHEN f.FAB_NAME like 'CZ4:%' or f.FAB_NAME like 'ISMFAB:%' or f.FAB_NAME like 'UVA:%' or f.FAB_NAME like 'LFOUNDRY'
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, 7)
            WHEN (f.FAB_NAME like 'UMC:%' or f.FAB_NAME like 'MYD:%' ) and regexp_like(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '^.+\.[0-9]+$')
            THEN SUBSTR(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, 1, instr(CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END, '.')-1)
            WHEN sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT
            ELSE t.PARENT_LOT
       END order by TRANS_DT) as dr
FROM translate t
LEFT JOIN src_lot sl ON t.PARENT_LOT = sl.LOT
LEFT JOIN fab_info f on CASE when sl.SOURCE_LOT IS NOT NULL THEN sl.SOURCE_LOT ELSE t.PARENT_LOT END = f.LOT
WHERE t.LOT in (:lotid)
)
WHERE DR=1
"""


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        logging.critical("Script failed: %s", exc, exc_info=True)
        print(f"Script failed: {exc}", file=sys.stderr)
        sys.exit(3)
