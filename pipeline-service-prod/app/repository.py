import os
import json
from typing import List, Optional
from datetime import datetime
from collections import defaultdict
from .models import PipelineInfo, PipelineSummary
from .parsers import get_parser
import json as _json

def get_repository(backend: str):
    if backend == "jsonl":
        return JsonlPipelineRepository()
    return OraclePipelineRepository()

class PipelineInfoRepository:
    def get_pipeline_info(self, start_utc: Optional[str], end_utc: Optional[str], min_rowcount: Optional[int], max_rowcount: Optional[int], limit: Optional[int], offset: int, pipeline_name: Optional[str] = None, script_name: Optional[str] = None, pipeline_type: Optional[str] = None, environment: Optional[str] = None) -> List[PipelineInfo]:
        raise NotImplementedError

    def count_pipeline_info(self, start_utc: Optional[str], end_utc: Optional[str], min_rowcount: Optional[int], max_rowcount: Optional[int], pipeline_name: Optional[str] = None, script_name: Optional[str] = None, pipeline_type: Optional[str] = None, environment: Optional[str] = None) -> int:
        raise NotImplementedError
    
    def get_pipelines_summary(self) -> List[PipelineSummary]:
        raise NotImplementedError
    
    def insert_pipeline_info(self, record: PipelineInfo) -> None:
        """Insert a single PipelineInfo record into the backend."""
        raise NotImplementedError

    def insert_raw_pipeline_record(self, record: dict) -> None:
        """Insert a raw record dict (possibly containing diagnostics/benchmark strings).

        This method will run a parser plugin if available to extract structured
        `metadata` and `benchmark` and then persist the resulting PipelineInfo.
        """
        raise NotImplementedError

    def get_pipeline_info_by_date_code(self, date_code: str) -> Optional[PipelineInfo]:
        """Fetch a single PipelineInfo record by date_code for secure file serving."""
        raise NotImplementedError

class JsonlPipelineRepository(PipelineInfoRepository):
    def __init__(self):
        self.filepath = os.environ.get("PIPELINE_JSONL_PATH", "pipeline_data.jsonl")

    def _read_all(self) -> List[PipelineInfo]:
        if not os.path.exists(self.filepath):
            return []
        
        data = []
        with open(self.filepath, "r", encoding="utf-8") as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    record_data = json.loads(line)
                    # Handle backward compatibility - set defaults for missing fields
                    if 'pipeline_name' not in record_data:
                        record_data['pipeline_name'] = self._infer_pipeline_name(record_data)
                    # Ensure new extensible fields exist so downstream code can rely on them
                    if 'metadata' not in record_data:
                        record_data['metadata'] = {}
                    if 'benchmark' not in record_data:
                        record_data['benchmark'] = {}
                    # Let Pydantic parse datetime strings into datetime objects
                    data.append(PipelineInfo(**record_data))
                except (json.JSONDecodeError, ValueError) as e:
                    print(f"Warning: Skipping invalid line {line_num}: {e}")
                    continue
        return data

    def _infer_pipeline_name(self, record_data: dict) -> Optional[str]:
        """Infer pipeline name from existing data for backward compatibility"""
        output_file = record_data.get('output_file', '')
        log_file = record_data.get('log_file', '')
        
        # Try to extract from output file path
        if output_file and '/pipeline/' in output_file:
            # Extract from path like "/apps/data/pipeline/sales_etl/output-20250808.data"
            parts = output_file.split('/')
            for i, part in enumerate(parts):
                if part == 'pipeline' and i + 1 < len(parts):
                    next_part = parts[i + 1]
                    if not next_part.startswith('output-'):
                        return next_part
        
        # Try to extract from log file path
        if log_file and '/logs/' in log_file:
            # Extract from path like "/apps/data/pipeline/logs/sales_etl-20250808.log"
            filename = log_file.split('/')[-1]
            if '-' in filename:
                return filename.split('-')[0]
        
        return "unknown"

    def _apply_filters(self, data: List[PipelineInfo], start_utc: Optional[datetime], end_utc: Optional[datetime], min_rowcount: Optional[int], max_rowcount: Optional[int], pipeline_name: Optional[str], script_name: Optional[str], pipeline_type: Optional[str], environment: Optional[str]):
        """Apply all filters to the data"""
        return [
            rec for rec in data
            if (not start_utc or rec.start_utc >= start_utc)
            and (not end_utc or rec.end_utc <= end_utc)
            and (min_rowcount is None or rec.rowcount >= min_rowcount)
            and (max_rowcount is None or rec.rowcount <= max_rowcount)
            and (not pipeline_name or rec.pipeline_name == pipeline_name)
            and (not script_name or rec.script_name == script_name)
            and (not pipeline_type or rec.pipeline_type == pipeline_type)
            and (not environment or rec.environment == environment)
        ]

    def get_pipeline_info(self, start_utc, end_utc, min_rowcount, max_rowcount, limit, offset, pipeline_name=None, script_name=None, pipeline_type=None, environment=None):
        data = self._read_all()
        filtered = self._apply_filters(data, start_utc, end_utc, min_rowcount, max_rowcount, pipeline_name, script_name, pipeline_type, environment)
        # start_utc is a datetime; safe to sort directly
        filtered.sort(key=lambda r: r.start_utc, reverse=True)

        if limit is not None:
            return filtered[offset:offset+limit]
        return filtered[offset:]

    def count_pipeline_info(self, start_utc, end_utc, min_rowcount, max_rowcount, pipeline_name=None, script_name=None, pipeline_type=None, environment=None):
        data = self._read_all()
        filtered = self._apply_filters(data, start_utc, end_utc, min_rowcount, max_rowcount, pipeline_name, script_name, pipeline_type, environment)
        return len(filtered)

    def get_pipelines_summary(self) -> List[PipelineSummary]:
        data = self._read_all()
        
        # Group by pipeline characteristics
        groups = defaultdict(list)
        for record in data:
            key = (record.pipeline_name, record.script_name, record.pipeline_type, record.environment)
            groups[key].append(record)
        
        summaries = []
        for (pipeline_name, script_name, pipeline_type, environment), records in groups.items():
            if not records:
                continue

            # Calculate statistics
            total_runs = len(records)
            durations = [r.elapsed_seconds for r in records if r.elapsed_seconds > 0]
            rowcounts = [r.rowcount for r in records if r.rowcount > 0]

            # Get latest run
            latest_record = max(records, key=lambda r: r.start_utc)

            summary = PipelineSummary(
                pipeline_name=pipeline_name,
                script_name=script_name,
                pipeline_type=pipeline_type,
                environment=environment,
                total_runs=total_runs,
                last_run=latest_record.start_utc,
                avg_duration=sum(durations) / len(durations) if durations else None,
                avg_rowcount=sum(rowcounts) / len(rowcounts) if rowcounts else None
            )
            summaries.append(summary)
        
        # Sort by last run time (most recent first)
        summaries.sort(key=lambda s: s.last_run or "", reverse=True)
        return summaries

    def insert_pipeline_info(self, record: PipelineInfo) -> None:
        """Append a record to the JSONL file. Serializes datetimes to ISO format."""
        # Ensure parent dir exists
        dirpath = os.path.dirname(self.filepath)
        if dirpath and not os.path.exists(dirpath):
            os.makedirs(dirpath, exist_ok=True)

        # Use Pydantic's model_dump to get serializable data
        data = record.model_dump()
        # Convert datetimes to ISO format strings
        for k, v in list(data.items()):
            if isinstance(v, (list, dict)):
                continue
            try:
                # datetime -> isoformat
                if hasattr(v, 'isoformat'):
                    data[k] = v.isoformat()
            except Exception:
                pass

        with open(self.filepath, 'a', encoding='utf-8') as f:
            f.write(json.dumps(data, ensure_ascii=False) + "\n")

    def insert_raw_pipeline_record(self, record: dict) -> None:
        # Run parser plugin if available
        parser = get_parser(record.get('script_name'), record.get('pipeline_name'))
        if parser:
            parsed = parser.normalize_record(record)
            # merge parsed metadata/benchmark into record dict
            record_metadata = record.get('metadata', {}) or {}
            record_benchmark = record.get('benchmark', {}) or {}
            # parsed contains keys 'metadata' and 'benchmark'
            record['metadata'] = {**record_metadata, **parsed.get('metadata', {})}
            record['benchmark'] = {**record_benchmark, **parsed.get('benchmark', {})}

        # Ensure pipeline_name default
        if 'pipeline_name' not in record:
            record['pipeline_name'] = self._infer_pipeline_name(record)

        # Let Pydantic validate/convert and then append
        rec = PipelineInfo(**record)
        return self.insert_pipeline_info(rec)

    def get_pipeline_info_by_date_code(self, date_code: str) -> Optional[PipelineInfo]:
        data = self._read_all()
        for record in data:
            if record.date_code == date_code:
                return record
        return None

class OraclePipelineRepository(PipelineInfoRepository):
    def __init__(self):
        self.dsn = os.environ.get("ORACLE_DSN")
        self.user = os.environ.get("ORACLE_USER")
        self.password = os.environ.get("ORACLE_PASSWORD")
        self.table = os.environ.get("ORACLE_TABLE", "PIPELINE_RUNS")
        # Optional JSON mapping from model field names to DB column names
        # Example: {"start_utc": "START_UTC_COL", "rowcount": "ROW_COUNT"}
        col_map_raw = os.environ.get("ORACLE_COLUMN_MAP")
        if col_map_raw:
            try:
                self.column_map = json.loads(col_map_raw)
            except Exception:
                self.column_map = {}
        else:
            self.column_map = {}
        
        if not all([self.dsn, self.user, self.password]):
            raise ValueError("Missing Oracle connection parameters: ORACLE_DSN, ORACLE_USER, ORACLE_PASSWORD")
        
        try:
            import oracledb
            # Use Thin mode by default; can be upgraded transparently if Oracle Client libs are present
            self._driver = oracledb
        except ImportError:
            raise ImportError("python-oracledb package required for Oracle backend. Install with: pip install python-oracledb")

    def _build_where(self, start_utc, end_utc, min_rowcount, max_rowcount, pipeline_name, script_name, pipeline_type, environment):
        where = []
        params = {}
        
        if start_utc:
            col = self.column_map.get('start_utc', 'start_utc')
            where.append(f"{col} >= :start_utc")
            params["start_utc"] = start_utc
        if end_utc:
            col = self.column_map.get('end_utc', 'end_utc')
            where.append(f"{col} <= :end_utc")
            params["end_utc"] = end_utc
        if min_rowcount is not None:
            where.append("rowcount >= :min_rowcount")
            params["min_rowcount"] = min_rowcount
        if max_rowcount is not None:
            where.append("rowcount <= :max_rowcount")
            params["max_rowcount"] = max_rowcount
        if pipeline_name:
            col = self.column_map.get('pipeline_name', 'pipeline_name')
            where.append(f"{col} = :pipeline_name")
            params["pipeline_name"] = pipeline_name
        if script_name:
            col = self.column_map.get('script_name', 'script_name')
            where.append(f"{col} = :script_name")
            params["script_name"] = script_name
        if pipeline_type:
            col = self.column_map.get('pipeline_type', 'pipeline_type')
            where.append(f"{col} = :pipeline_type")
            params["pipeline_type"] = pipeline_type
        if environment:
            col = self.column_map.get('environment', 'environment')
            where.append(f"{col} = :environment")
            params["environment"] = environment
            
        return where, params

    def get_pipeline_info(self, start_utc, end_utc, min_rowcount, max_rowcount, limit, offset, pipeline_name=None, script_name=None, pipeline_type=None, environment=None):
        where, params = self._build_where(start_utc, end_utc, min_rowcount, max_rowcount, pipeline_name, script_name, pipeline_type, environment)
        # Select columns using mapping if provided, else select *
        if self.column_map:
            select_cols = ",".join([f"{v} as {k}" for k, v in self.column_map.items()])
            sql = f"SELECT {select_cols} FROM {self.table}"
        else:
            sql = f"SELECT * FROM {self.table}"
        if where:
            sql += " WHERE " + " AND ".join(where)
        sql += " ORDER BY start_utc DESC"
        
        if limit is not None:
            sql = f"""
                SELECT * FROM (
                  SELECT a.*, ROWNUM rnum FROM ({sql}) a WHERE ROWNUM <= :max_row
                ) WHERE rnum > :min_row
            """
            params["max_row"] = offset + limit
            params["min_row"] = offset

        conn = self._driver.connect(user=self.user, password=self.password, dsn=self.dsn)
        try:
            cur = conn.cursor()
            cur.execute(sql, params)
            cols = [c[0].lower() for c in cur.description]
            results = []
            for row in cur.fetchall():
                record_dict = dict(zip(cols, row))
                # Parse JSON CLOB fields
                for clob_json_field in ['metadata', 'benchmark']:
                    if clob_json_field in record_dict and record_dict[clob_json_field]:
                        try:
                            if hasattr(record_dict[clob_json_field], 'read'):
                                record_dict[clob_json_field] = json.loads(record_dict[clob_json_field].read())
                            elif isinstance(record_dict[clob_json_field], str):
                                record_dict[clob_json_field] = json.loads(record_dict[clob_json_field])
                        except:
                            pass
                
                # Handle non-JSON CLOB fields (status messages, run args)
                for clob_text_field in ['error_message', 'run_args']:
                    if clob_text_field in record_dict and record_dict[clob_text_field]:
                        if hasattr(record_dict[clob_text_field], 'read'):
                            record_dict[clob_text_field] = record_dict[clob_text_field].read()

                # Parse other JSON fields (which might be CLOBs in some environments)
                for json_field in ['output_files_gen', 'output_files_trace', 'archived_gen_files', 'archived_trace_files', 'out_files']:
                    if json_field in record_dict and record_dict[json_field]:
                        try:
                            if hasattr(record_dict[json_field], 'read'):
                                record_dict[json_field] = json.loads(record_dict[json_field].read())
                            elif isinstance(record_dict[json_field], str):
                                record_dict[json_field] = json.loads(record_dict[json_field])
                        except:
                            pass
                
                rec = PipelineInfo(**record_dict)
                # Enrich with computed fields
                from .utils import enrich_pipeline_info
                rec = enrich_pipeline_info(rec)
                results.append(rec)
            return results
        finally:
            conn.close()

    def count_pipeline_info(self, start_utc, end_utc, min_rowcount, max_rowcount, pipeline_name=None, script_name=None, pipeline_type=None, environment=None):
        where, params = self._build_where(start_utc, end_utc, min_rowcount, max_rowcount, pipeline_name, script_name, pipeline_type, environment)
        sql = f"SELECT COUNT(*) FROM {self.table}"
        if where:
            sql += " WHERE " + " AND ".join(where)
            
        conn = self._driver.connect(user=self.user, password=self.password, dsn=self.dsn)
        try:
            cur = conn.cursor()
            cur.execute(sql, params)
            return cur.fetchone()[0]
        finally:
            conn.close()

    def get_pipelines_summary(self) -> List[PipelineSummary]:
        sql = f"""
            SELECT 
                pipeline_name,
                script_name,
                pipeline_type,
                environment,
                COUNT(*) as total_runs,
                MAX(start_utc) as last_run,
                AVG(elapsed_seconds) as avg_duration,
                AVG(rowcount) as avg_rowcount
            FROM {self.table}
            GROUP BY pipeline_name, script_name, pipeline_type, environment
            ORDER BY last_run DESC
        """
        
        conn = self._driver.connect(user=self.user, password=self.password, dsn=self.dsn)
        try:
            cur = conn.cursor()
            cur.execute(sql)
            cols = [c[0].lower() for c in cur.description]
            results = []
            for row in cur.fetchall():
                data = dict(zip(cols, row))
                results.append(PipelineSummary(**data))
            return results
        finally:
            conn.close()

    def insert_pipeline_info(self, record: PipelineInfo) -> None:
        """Insert a single PipelineInfo record into the Oracle table.

        This performs a simple INSERT using named binds. The table must have
        columns that match the model field names (lowercase), or adjust the
        mapping accordingly.
        """
        # Map model fields to a dict of values
        data = record.model_dump()
        # Keep Python datetime objects as-is so DB driver can bind them as TIMESTAMP
        # Build column list (DB column names) but use model field names as bind
        # placeholders. That way the mapping can map model fields to arbitrary
        # DB column names while binds remain predictable.
        cols = []
        bind_placeholders = []
        binds = {}
        for k, v in data.items():
            db_col = self.column_map.get(k, k)
            cols.append(db_col)
            bind_placeholders.append(f":{k}")
            
            # Handle different data types for Oracle binding
            if v is None:
                binds[k] = None
            elif k in ("metadata", "benchmark"):
                # Always serialize metadata/benchmark to JSON string for CLOB
                if isinstance(v, (dict, list)):
                    binds[k] = _json.dumps(v)
                elif isinstance(v, str):
                    # Already a string, use as-is
                    binds[k] = v
                else:
                    # Convert to JSON string
                    binds[k] = _json.dumps(v)
            elif isinstance(v, (dict, list)):
                # Any other dict/list fields should be serialized to JSON
                binds[k] = _json.dumps(v)
            elif hasattr(v, 'isoformat'):
                # Keep datetime objects as-is for proper TIMESTAMP binding
                binds[k] = v
            else:
                # Primitive types (str, int, float, bool) can be bound directly
                binds[k] = v

        col_list = ",".join(cols)
        bind_list = ",".join(bind_placeholders)
        sql = f"INSERT INTO {self.table} ({col_list}) VALUES ({bind_list})"

        conn = self._driver.connect(user=self.user, password=self.password, dsn=self.dsn)
        try:
            cur = conn.cursor()
            cur.execute(sql, binds)
            conn.commit()
        finally:
            conn.close()

    def get_pipeline_info_by_date_code(self, date_code: str) -> Optional[PipelineInfo]:
        sql = f"SELECT * FROM {self.table} WHERE date_code = :date_code"
        conn = self._driver.connect(user=self.user, password=self.password, dsn=self.dsn)
        try:
            cur = conn.cursor()
            cur.execute(sql, {"date_code": date_code})
            row = cur.fetchone()
            if row:
                cols = [c[0].lower() for c in cur.description]
                record_dict = dict(zip(cols, row))
                # Parse JSON CLOB fields (dict-type)
                for clob_json_field in ['metadata', 'benchmark']:
                    if clob_json_field in record_dict and record_dict[clob_json_field]:
                        try:
                            if hasattr(record_dict[clob_json_field], 'read'):
                                record_dict[clob_json_field] = json.loads(record_dict[clob_json_field].read())
                            elif isinstance(record_dict[clob_json_field], str):
                                record_dict[clob_json_field] = json.loads(record_dict[clob_json_field])
                        except:
                            pass
                # Handle non-JSON CLOB fields (plain text)
                for clob_text_field in ['error_message', 'run_args']:
                    if clob_text_field in record_dict and record_dict[clob_text_field]:
                        if hasattr(record_dict[clob_text_field], 'read'):
                            record_dict[clob_text_field] = record_dict[clob_text_field].read()
                # Parse JSON array CLOB fields (list-type)
                for json_field in ['output_files_gen', 'output_files_trace', 'archived_gen_files', 'archived_trace_files', 'out_files']:
                    if json_field in record_dict and record_dict[json_field]:
                        try:
                            if hasattr(record_dict[json_field], 'read'):
                                record_dict[json_field] = json.loads(record_dict[json_field].read())
                            elif isinstance(record_dict[json_field], str):
                                record_dict[json_field] = json.loads(record_dict[json_field])
                        except:
                            pass
                rec = PipelineInfo(**record_dict)
                from .utils import enrich_pipeline_info
                rec = enrich_pipeline_info(rec)
                return rec
            return None
        finally:
            conn.close()
