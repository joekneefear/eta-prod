"""Pytest configuration and fixtures for Scribe-Lot-Mapper tests.

This module provides shared fixtures and configuration for all test modules,
including sample data, mock objects, and utility functions.
"""

from datetime import datetime
from pathlib import Path
from typing import Generator, List

import pytest

from scribe_lot_mapper.models import (
    EquipmentInfo,
    LotAttributeRecord,
    LotHistoryRecord,
    MappingRecord,
    ParsedRecord,
)


# ============================================================================
# Sample Data Fixtures
# ============================================================================


@pytest.fixture
def sample_parsed_record() -> ParsedRecord:
    """Create a sample parsed record from workstream data.

    Returns:
        ParsedRecord: Sample record with typical workstream values
    """
    return ParsedRecord(
        raw_line="GMBG3002\t1.0\tJUL 14 2026 03:00:16:000AM\t26WW\tBUCHEON\tVF_TEST\t1\tLEFT\tTHK-1-51T\t301.2\t4.9\t5.7\t5.7\t5.4\t100\t50",
        parameter_set_id="GMBG3002",
        parameter_set_version="1.0",
        date_time="JUL 14 2026 03:00:16:000AM",
        facility="BUCHEON",
        parameter_name="VF_TEST",
        sequence_number=1,
        unit_id="LEFT",
        type_id="THK-1-51T",
        c_values=["301.2", "4.9", "5.7", "5.7", "5.4"],
        d_values=["100"],
        limits_high="500",
        limits_low="0",
        timestamp="2026-07-14T03:00:16Z",
    )


@pytest.fixture
def sample_equipment_info() -> EquipmentInfo:
    """Create a sample equipment info from decomposed equipment code.

    Returns:
        EquipmentInfo: Sample equipment with typical pattern
    """
    return EquipmentInfo(
        raw_code="THK-1-51T",
        facility="THK",
        probe=1,
        position=51,
        type="T",
        normalized_code="THK_1_51_T",
    )


@pytest.fixture
def sample_mapping_record() -> MappingRecord:
    """Create a sample mapping record.

    Returns:
        MappingRecord: Complete mapping with all relationships
    """
    return MappingRecord(
        mapping_id="550e8400-e29b-41d4-a716-446655440001",
        scribe_id="THK_1_51_LEFT_1",
        lot_id="KG4BNTCX",
        wafer_id="GOXTWS1125",
        test_program="GMBG3002",
        equipment_id="THK-1-51T",
        facility="BUCHEON",
        timestamp="2026-07-14T03:00:16Z",
        created_at="2026-07-14T03:15:00Z",
        wafer_family="GOXTWS",
        wafer_batch=1125,
        test_value="301.2",
        sequence_number=1,
        site_number=1,
        unit_id="LEFT",
        validation_status="valid",
        parent_mapping_id=None,
    )


@pytest.fixture
def sample_lot_history_record() -> LotHistoryRecord:
    """Create a sample lot history record.

    Returns:
        LotHistoryRecord: Sample lot movement record
    """
    return LotHistoryRecord(
        lot_id="KG4BNTCX",
        operation="MOVE",
        transaction_type="MVOU",
        quantity=25,
        equipment_id="THK-1-51T",
        timestamp="2026-07-14T03:00:16Z",
    )


@pytest.fixture
def sample_lot_attribute_record() -> LotAttributeRecord:
    """Create a sample lot attribute record.

    Returns:
        LotAttributeRecord: Sample lot custom attribute
    """
    return LotAttributeRecord(
        lot_id="KG4BNTCX",
        attribute_name="EPI SLOT",
        attribute_value="A6",
        attribute_type="A",
    )


# ============================================================================
# Test Data Collections
# ============================================================================


@pytest.fixture
def sample_parsed_records() -> List[ParsedRecord]:
    """Create multiple sample parsed records.

    Returns:
        List[ParsedRecord]: Collection of records with variety of values
    """
    return [
        ParsedRecord(
            raw_line=f"GMBG3002\t1.0\tJUL 14 2026 03:00:1{i}:000AM\t26WW\tBUCHEON\tVF_TEST\t{i}\tLEFT\tTHK-1-51T\t{300+i}.2\t4.9\t5.7\t5.7\t5.4\t100\t50",
            parameter_set_id="GMBG3002",
            parameter_set_version="1.0",
            date_time=f"JUL 14 2026 03:00:1{i}:000AM",
            facility="BUCHEON",
            parameter_name="VF_TEST",
            sequence_number=i,
            unit_id="LEFT",
            type_id="THK-1-51T",
            c_values=["301.2", "4.9", "5.7", "5.7", "5.4"],
            d_values=["100"],
            limits_high="500",
            limits_low="0",
            timestamp=f"2026-07-14T03:00:1{i}Z",
        )
        for i in range(5)
    ]


@pytest.fixture
def sample_mapping_records() -> List[MappingRecord]:
    """Create multiple sample mapping records.

    Returns:
        List[MappingRecord]: Collection of mappings with variety
    """
    records = []
    for i in range(3):
        records.append(
            MappingRecord(
                mapping_id=f"550e8400-e29b-41d4-a716-{446655440001+i:012d}",
                scribe_id=f"THK_1_51_LEFT_{i+1}",
                lot_id=f"KG4BNTC{chr(88+i)}",
                wafer_id=f"GOXTWS{1125+i*10}",
                test_program="GMBG3002",
                equipment_id="THK-1-51T",
                facility="BUCHEON",
                timestamp=f"2026-07-14T03:00:{10+i:02d}Z",
                created_at="2026-07-14T03:15:00Z",
                wafer_family="GOXTWS",
                wafer_batch=1125 + i * 10,
                test_value=f"{300+i}.2",
                sequence_number=i,
                site_number=1,
                unit_id="LEFT",
                validation_status="valid",
                parent_mapping_id=None,
            )
        )
    return records


# ============================================================================
# Path/File Fixtures
# ============================================================================


@pytest.fixture
def tmp_work_dir(tmp_path: Path) -> Path:
    """Create a temporary working directory for tests.

    Args:
        tmp_path: pytest's built-in tmp_path fixture

    Returns:
        Path: Temporary directory path
    """
    work_dir = tmp_path / "work"
    work_dir.mkdir(parents=True, exist_ok=True)
    return work_dir


@pytest.fixture
def sample_input_file(tmp_work_dir: Path) -> Path:
    """Create a sample input file with test records.

    Args:
        tmp_work_dir: Temporary working directory

    Returns:
        Path: Path to sample input file
    """
    input_file = tmp_work_dir / "sample_input.phist"

    # Create sample workstream data
    lines = [
        "GMBG3002\t1.0\tJUL 14 2026 03:00:16:000AM\t26WW\tBUCHEON\tVF_TEST\t1\tLEFT\tTHK-1-51T\t301.2\t4.9\t5.7\t5.7\t5.4\t100\t50",
        "GMBG3002\t1.0\tJUL 14 2026 03:00:17:000AM\t26WW\tBUCHEON\tVF_TEST\t2\tCENTER\tTHK-1-51F\t302.1\t5.0\t5.8\t5.8\t5.5\t100\t50",
        "GTGX9A510_501\t2.1\tJUL 14 2026 03:00:18:000AM\t26WW\tBUCHEON\tGTGX_TEST\t1\tRIGHT\tRI-1-11\t150.5\t\t\t\t\t200\t100",
    ]

    with open(input_file, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    return input_file


@pytest.fixture
def output_dir(tmp_work_dir: Path) -> Path:
    """Create output directory for tests.

    Args:
        tmp_work_dir: Temporary working directory

    Returns:
        Path: Output directory path
    """
    out_dir = tmp_work_dir / "output"
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir


# ============================================================================
# Mock/Stub Fixtures
# ============================================================================


@pytest.fixture
def mock_logger() -> "MockLogger":
    """Create a mock logger for testing.

    Returns:
        MockLogger: Mock logger that tracks method calls
    """

    class MockLogger:
        """Mock logger for testing."""

        def __init__(self) -> None:
            self.messages: List[str] = []
            self.errors: List[str] = []
            self.warnings: List[str] = []

        def info(self, msg: str) -> None:
            """Log info message."""
            self.messages.append(msg)

        def error(self, msg: str, exc_info: bool = False) -> None:
            """Log error message."""
            self.errors.append(msg)

        def warning(self, msg: str) -> None:
            """Log warning message."""
            self.warnings.append(msg)

        def debug(self, msg: str) -> None:
            """Log debug message."""
            self.messages.append(msg)

        def critical(self, msg: str) -> None:
            """Log critical message."""
            self.errors.append(msg)

    return MockLogger()


# ============================================================================
# Pytest Hooks
# ============================================================================


def pytest_configure(config: pytest.Config) -> None:
    """Configure pytest with custom markers.

    Args:
        config: pytest configuration object
    """
    config.addinivalue_line("markers", "unit: mark test as unit test")
    config.addinivalue_line("markers", "integration: mark test as integration test")
    config.addinivalue_line("markers", "property: mark test as property-based test")
    config.addinivalue_line("markers", "slow: mark test as slow running")
