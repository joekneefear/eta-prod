from app.parsers.e142_parser import E142Parser

DIAG_LINE = (
    "E142 extraction diagnostics: fetched=580 kept=580 dropped_status=0 "
    "dropped_no_backend_lot=0 dropped_prod_regex=0 files_written=1 "
    "stage=WAFER flow=B1T view=ANALYTICSPRD.MFG.E142_VN5_B1T_EXENSIO_FAB2PUCK_RPT"
)

BENCH_LINE = '{"start_local":"2026-02-25 00:00:00","end_local":"2026-02-25 00:00:10","elapsed_seconds":10,"rows_extracted":580}'


def test_parse_diagnostics_line():
    p = E142Parser()
    md = p.parse_diagnostics_line(DIAG_LINE)
    assert md is not None
    assert md["fetched"] == 580
    assert md["kept"] == 580
    assert md["files_written"] == 1
    assert md["stage"] == "WAFER"
    assert md["flow"] == "B1T"


def test_parse_benchmark_line():
    p = E142Parser()
    bk = p.parse_benchmark_line(BENCH_LINE)
    assert bk is not None
    assert bk["elapsed_seconds"] == 10
    assert bk["rows_extracted"] == 580
