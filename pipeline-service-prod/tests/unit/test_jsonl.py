from tempfile import NamedTemporaryFile
import os

from app.models import PipelineInfo
from app.utils import read_jsonl, write_jsonl_append

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


def test_jsonl_append_and_read():
    rec = PipelineInfo(**SAMPLE)
    ntf = NamedTemporaryFile(delete=False)
    path = ntf.name
    ntf.close()

    # Write using util
    write_jsonl_append(path, rec)

    loaded = read_jsonl(path)
    assert len(loaded) == 1
    assert loaded[0].rowcount == rec.rowcount

    os.remove(path)
