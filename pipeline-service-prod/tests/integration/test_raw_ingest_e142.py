import importlib
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile
from fastapi.testclient import TestClient


SAMPLE_RAW = {
    "script_name": "n_getSnowflakeE142ModuleTrace.pl",
    "pipeline_name": "getSnowflakeE142ModuleTrace",
    "diagnostics_line": "E142 extraction diagnostics: fetched=580 kept=580 dropped_status=0 dropped_no_backend_lot=0 dropped_prod_regex=0 files_written=1 stage=WAFER flow=B1T view=ANALYTICSPRD.MFG.E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT",
    "benchmark_line": '{"start_local":"2026-02-25 00:00:00","end_local":"2026-02-25 00:00:10","elapsed_seconds":10,"rows_extracted":580}'
}


def test_raw_ingest_e142(monkeypatch, tmp_path):
    # Ensure repo root is importable
    repo_root = str(Path(__file__).resolve().parents[2])
    if repo_root not in sys.path:
        sys.path.insert(0, repo_root)

    main_module = importlib.import_module('main')
    client = TestClient(main_module.main_app)

    # Prepare a Jsonl repo with a temp file
    repo_module = importlib.import_module('app.repository')
    JsonlRepo = repo_module.JsonlPipelineRepository
    repo = JsonlRepo()
    ntf = NamedTemporaryFile(delete=False)
    repo.filepath = ntf.name
    ntf.close()

    # Monkeypatch global REPO in main
    monkeypatch.setattr(main_module, 'REPO', repo)

    resp = client.post('/v1/pipelines/raw', json=SAMPLE_RAW)
    assert resp.status_code == 201

    # Ensure the JSONL file contains the record and metadata/benchmark keys
    from app.utils import read_jsonl
    loaded = read_jsonl(repo.filepath)
    assert len(loaded) == 1
    rec = loaded[0]
    assert hasattr(rec, 'metadata')
    assert hasattr(rec, 'benchmark')

    # cleanup
    import os
    os.remove(repo.filepath)
