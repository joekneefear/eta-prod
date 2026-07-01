from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

class PipelineInfo(BaseModel):
    # Use datetime for timestamps so Pydantic/ FastAPI will parse and validate them
    start_local: datetime = Field(..., description="Start time in local timezone")
    end_local: datetime = Field(..., description="End time in local timezone")
    start_utc: datetime = Field(..., description="Start time in UTC (ISO format)")
    end_utc: datetime = Field(..., description="End time in UTC (ISO format)")
    elapsed_seconds: float = Field(..., description="Duration in seconds")
    elapsed_human: str = Field(..., description="Human readable duration (e.g., '22m 5s')")
    output_file: Optional[str] = Field(None, description="Path to output data file")
    rowcount: int = Field(..., description="Number of rows processed")
    log_file: str = Field(..., description="Path to log file")
    pid: int = Field(..., description="Process ID")
    date_code: str = Field(..., description="Unique date code identifier")
    
    # New pipeline identification fields
    pipeline_name: Optional[str] = Field(None, description="Name of the pipeline (e.g., 'data_ingestion', 'etl_transform')")
    script_name: Optional[str] = Field(None, description="Name of the script file (e.g., 'process_sales.py')")
    pipeline_type: Optional[str] = Field(None, description="Type of pipeline (e.g., 'batch', 'streaming', 'ml')")
    environment: Optional[str] = Field(None, description="Environment (e.g., 'prod', 'dev', 'test')")
    
    # New archived file field
    archived_file: Optional[str] = Field(None, description="Path to the archived file (e.g., compressed output)")

    # Multi-output fields (per type) for newer JSONL format
    output_file_gen: Optional[str] = Field(None, description="Single output file for genealogy (non-archive)")
    output_files_gen: Optional[List[str]] = Field(None, description="Multiple output files for genealogy (non-archive)")
    output_file_trace: Optional[str] = Field(None, description="Single output file for trace (non-archive)")
    output_files_trace: Optional[List[str]] = Field(None, description="Multiple output files for trace (non-archive)")
    archived_gen_files: Optional[List[str]] = Field(None, description="Archived genealogy files")
    archived_trace_files: Optional[List[str]] = Field(None, description="Archived trace files")
    
    # Row count metrics for detailed tracking
    rows_extracted: Optional[int] = Field(None, description="Number of rows extracted from source")
    rows_written: Optional[int] = Field(None, description="Number of rows written to output files")
    total_files: Optional[int] = Field(None, description="Total number of output files generated")
    out_files: Optional[List[dict]] = Field(None, description="Detailed output file information with row counts (path, rows)")

    # Arbitrary metadata and benchmark fields to support new/extended scripts (E142, etc.)
    metadata: Optional[dict] = Field(None, description="Arbitrary script diagnostics and metadata (dict)")
    benchmark: Optional[dict] = Field(None, description="Benchmark/monitoring information emitted by script (dict)")
    
    # New execution tracking fields (matched to Oracle schema update)
    status: Optional[str] = Field(None, description="Run status (e.g., 'success', 'error', 'partial')")
    error_message: Optional[str] = Field(None, description="Detailed error message if status is 'error'")
    hostname: Optional[str] = Field(None, description="Hostname where the script executed")
    run_args: Optional[str] = Field(None, description="Full command-line arguments used for the run")

    # Computed fields for E142 file type breakdown (extracted from metadata)
    file_type_counts: Optional[dict] = Field(None, description="E142 trace file counts by type (w2f, a2w, f2w, etc.)")
    file_type_rows: Optional[dict] = Field(None, description="E142 trace file row counts by type")

    # Pydantic v2 model config
    model_config = {
        # allow building models from ORM objects/attribute-accessible objects
        "from_attributes": True,
        "json_schema_extra": {
            "example": {
                "start_local": "2025-09-02 05:07:02",
                "end_local": "2025-09-02 05:47:27",
                "start_utc": "2025-09-02T12:07:02Z",
                "end_utc": "2025-09-02T12:47:27Z",
                "elapsed_seconds": 2424.879,
                "elapsed_human": "40m 24s",
                "output_file": "/apps/exensio_data/reference_data/SubconLotRefData-20250902_050702.subconLot",
                "rowcount": 11060,
                "log_file": "/apps/exensio_data/reference_data/jag_test/log/getSubconLotRefData_LOTGDB.log",
                "pid": 21788,
                "date_code": "20250902_050702",
                "pipeline_name": "subcon_lotg_to_refdb_ingest",
                "script_name": "get_subcon_lot_ref_data_LOTGDB_rc10.py",
                "pipeline_type": "batch",
                "environment": "prod",
                "archived_file": "/apps/exensio_data/archives-yms/reference_data/lot/SubconLotRefData-20250902_050702.subconLot.gz",
                "output_file_gen": "",
                "output_files_gen": [],
                "output_file_trace": "",
                "output_files_trace": [],
                "archived_gen_files": ["/apps/exensio_data/archives-yms/reference_data/lot/SubconLotRefData-20250902_050702.subconLot.gz"],
                "archived_trace_files": []
                ,
                "metadata": {"rows_fetched": 0, "rows_kept": 0, "files_written": 0},
                "benchmark": {"elapsed_seconds": 0.0, "start_local": "", "end_local": ""}
            }
        }
    }

class PipelineInfoResponse(BaseModel):
    total: int = Field(..., description="Total number of matching records")
    count: int = Field(..., description="Number of records in this response")
    results: List[PipelineInfo] = Field(..., description="List of pipeline records")
    pipelines: List[str] = Field(default_factory=list, description="List of unique pipeline names in results")

class PipelineSummary(BaseModel):
    pipeline_name: Optional[str] = Field(..., description="Pipeline name")
    script_name: Optional[str] = Field(None, description="Script name")
    pipeline_type: Optional[str] = Field(None, description="Pipeline type")
    environment: Optional[str] = Field(None, description="Environment")
    total_runs: int = Field(..., description="Total number of runs")
    # last_run is a datetime so it can be sorted/compared programmatically
    last_run: Optional[datetime] = Field(None, description="Last run timestamp (UTC)")
    avg_duration: Optional[float] = Field(None, description="Average duration in seconds")
    avg_rowcount: Optional[float] = Field(None, description="Average rows processed")

class PipelineListResponse(BaseModel):
    pipelines: List[PipelineSummary] = Field(..., description="List of pipeline summaries")

