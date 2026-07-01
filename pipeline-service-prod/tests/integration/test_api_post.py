import os
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile
import importlib

SAMPLE = {
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
    "archived_file": "/apps/exensio_data/archives-yms/reference_data/lot/SubconLotRefData-20250902_050702.subconLot.gz"
}


def test_post_pipeline_inserts_jsonl(monkeypatch):
    # Ensure repo root is importable, then import main and TestClient inside the test
    repo_root = str(Path(__file__).resolve().parents[2])
    if repo_root not in sys.path:
        sys.path.insert(0, repo_root)

    main_module = importlib.import_module('main')
    from fastapi.testclient import TestClient
    from repository import JsonlPipelineRepository

    # Import utils after repo root is on sys.path
    utils = importlib.import_module('utils')
    read_jsonl = utils.read_jsonl

    client = TestClient(main_module.app)

    repo = JsonlPipelineRepository()
    ntf = NamedTemporaryFile(delete=False)
    repo.filepath = ntf.name
    ntf.close()

    # Monkeypatch global REPO in main
    monkeypatch.setattr(main_module, 'REPO', repo)

    resp = client.post('/pipelines', json=SAMPLE)
    assert resp.status_code == 201
    data = resp.json()
    assert data['rowcount'] == SAMPLE['rowcount']

    # Ensure the file contains the record
    loaded = read_jsonl(repo.filepath)
    assert len(loaded) == 1
    os.remove(repo.filepath)


def test_get_archived_file(monkeypatch):
    # Ensure repo root is importable
    repo_root = str(Path(__file__).resolve().parents[2])
    if repo_root not in sys.path:
        sys.path.insert(0, repo_root)

    main_module = importlib.import_module('main')
    from fastapi.testclient import TestClient
    from repository import JsonlPipelineRepository
    from models import PipelineInfo

    client = TestClient(main_module.app)

    repo = JsonlPipelineRepository()
    ntf = NamedTemporaryFile(delete=False)
    repo.filepath = ntf.name
    ntf.close()

    # Monkeypatch global REPO in main
    monkeypatch.setattr(main_module, 'REPO', repo)

    # Create a mock record with archived_file
    mock_record = PipelineInfo(**SAMPLE)
    
    # Modify the archived_file to use a local path for testing
    local_test_path = "/tmp/test_archived_file.gz"
    mock_record.archived_file = local_test_path
    
    # Create the file at the expected location
    with open(local_test_path, 'wb') as f:
        f.write(b"mock gz content")
    
    # Mock the get_pipeline_info_by_date_code method
    monkeypatch.setattr(repo, 'get_pipeline_info_by_date_code', lambda dc: mock_record if dc == SAMPLE['date_code'] else None)
    
    resp = client.get(f"/pipelines/archived/{SAMPLE['date_code']}")
    assert resp.status_code == 200
    # The filename should be extracted from the archived_file path
    expected_filename = Path(local_test_path).name
    assert f'filename="{expected_filename}"' in resp.headers["Content-Disposition"]
    assert resp.headers["Content-Type"] == "application/gzip"
    assert resp.content == b"mock gz content"
    
    # Clean up
    if os.path.exists(local_test_path):
        os.unlink(local_test_path)
    
    os.remove(repo.filepath)
