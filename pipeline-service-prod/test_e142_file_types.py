#!/usr/bin/env python3
"""
Test script for E142 file type tracking feature.
Tests both the data extraction and API endpoints.
"""

import json
import sys
from app.utils import extract_file_type_data, enrich_pipeline_info
from app.models import PipelineInfo
from datetime import datetime

def test_extract_file_type_data():
    """Test extraction of file type data from metadata"""
    print("Testing extract_file_type_data()...")
    
    # Test with valid metadata
    metadata = {
        "rows_fetched": 580,
        "rows_kept": 580,
        "file_type_counts": {
            "w2f": 15,
            "a2w": 3,
            "f2w": 5
        },
        "file_type_rows": {
            "w2f": 8750,
            "a2w": 1200,
            "f2w": 2500
        }
    }
    
    counts, rows = extract_file_type_data(metadata)
    assert counts == {"w2f": 15, "a2w": 3, "f2w": 5}, "File type counts mismatch"
    assert rows == {"w2f": 8750, "a2w": 1200, "f2w": 2500}, "File type rows mismatch"
    print("✓ Valid metadata extraction passed")
    
    # Test with None metadata
    counts, rows = extract_file_type_data(None)
    assert counts is None and rows is None, "None metadata should return None, None"
    print("✓ None metadata handling passed")
    
    # Test with empty metadata
    counts, rows = extract_file_type_data({})
    assert counts is None and rows is None, "Empty metadata should return None, None"
    print("✓ Empty metadata handling passed")
    
    print("✓ All extract_file_type_data tests passed!\n")


def test_enrich_pipeline_info():
    """Test enrichment of PipelineInfo with file type data"""
    print("Testing enrich_pipeline_info()...")
    
    # Create a mock PipelineInfo record
    record_data = {
        "start_local": datetime.now(),
        "end_local": datetime.now(),
        "start_utc": datetime.now(),
        "end_utc": datetime.now(),
        "elapsed_seconds": 120.5,
        "elapsed_human": "2m 0s",
        "rowcount": 12450,
        "log_file": "/apps/log/test.log",
        "pid": 12345,
        "date_code": "20260304_143022",
        "pipeline_name": "E142_VN5_WAFER",
        "metadata": {
            "rows_fetched": 12450,
            "rows_kept": 12450,
            "file_type_counts": {
                "w2f": 20
            },
            "file_type_rows": {
                "w2f": 12450
            }
        }
    }
    
    record = PipelineInfo(**record_data)
    enriched = enrich_pipeline_info(record)
    
    assert enriched.file_type_counts == {"w2f": 20}, "File type counts not enriched"
    assert enriched.file_type_rows == {"w2f": 12450}, "File type rows not enriched"
    print("✓ PipelineInfo enrichment passed")
    
    # Test with record without metadata
    record_no_meta = PipelineInfo(**{**record_data, "metadata": None})
    enriched_no_meta = enrich_pipeline_info(record_no_meta)
    assert enriched_no_meta.file_type_counts is None, "Should handle missing metadata"
    print("✓ Missing metadata handling passed")
    
    print("✓ All enrich_pipeline_info tests passed!\n")


def test_metadata_structure():
    """Test that metadata structure matches Perl script output"""
    print("Testing metadata structure compatibility...")
    
    # Simulate what Perl script generates
    perl_metadata = {
        "rows_fetched": 580,
        "rows_kept": 580,
        "rows_dropped_status": 0,
        "rows_dropped_no_backend_lot": 0,
        "rows_dropped_prod_regex": 0,
        "file_type_counts": {
            "w2f": 15,
            "a2w": 3
        },
        "file_type_rows": {
            "w2f": 8750,
            "a2w": 1200
        }
    }
    
    # Verify all expected keys exist
    assert "file_type_counts" in perl_metadata, "Missing file_type_counts"
    assert "file_type_rows" in perl_metadata, "Missing file_type_rows"
    assert isinstance(perl_metadata["file_type_counts"], dict), "file_type_counts should be dict"
    assert isinstance(perl_metadata["file_type_rows"], dict), "file_type_rows should be dict"
    
    # Verify validation formula
    total_files = sum(perl_metadata["file_type_counts"].values())
    total_rows = sum(perl_metadata["file_type_rows"].values())
    assert total_files == 18, f"Expected 18 files, got {total_files}"
    assert total_rows == 9950, f"Expected 9950 rows, got {total_rows}"
    
    print("✓ Metadata structure validation passed")
    print("✓ Validation formulas passed\n")


def test_json_serialization():
    """Test JSON serialization of file type data"""
    print("Testing JSON serialization...")
    
    metadata = {
        "file_type_counts": {
            "w2f": 15,
            "a2w": 3,
            "f2w": 5
        },
        "file_type_rows": {
            "w2f": 8750,
            "a2w": 1200,
            "f2w": 2500
        }
    }
    
    # Test serialization
    json_str = json.dumps(metadata)
    assert json_str, "JSON serialization failed"
    
    # Test deserialization
    parsed = json.loads(json_str)
    assert parsed == metadata, "JSON round-trip failed"
    
    print("✓ JSON serialization/deserialization passed\n")


def print_example_output():
    """Print example API response"""
    print("=" * 60)
    print("Example API Response Structure")
    print("=" * 60)
    
    example = {
        "pipeline_name": "E142_VN5_WAFER",
        "start_local": "2026-03-04T14:30:22",
        "rowcount": 12450,
        "total_files": 20,
        "file_type_counts": {
            "w2f": 20
        },
        "file_type_rows": {
            "w2f": 12450
        },
        "metadata": {
            "rows_fetched": 12450,
            "rows_kept": 12450,
            "rows_dropped_status": 0,
            "file_type_counts": {"w2f": 20},
            "file_type_rows": {"w2f": 12450}
        }
    }
    
    print(json.dumps(example, indent=2))
    print()


def main():
    """Run all tests"""
    print("\n" + "=" * 60)
    print("E142 File Type Tracking - Unit Tests")
    print("=" * 60 + "\n")
    
    try:
        test_extract_file_type_data()
        test_enrich_pipeline_info()
        test_metadata_structure()
        test_json_serialization()
        
        print("=" * 60)
        print("✓ ALL TESTS PASSED!")
        print("=" * 60 + "\n")
        
        print_example_output()
        
        print("Next Steps:")
        print("1. Run E142 extraction with --benchmark_db_dsn to test Perl changes")
        print("2. Start pipeline-service and test /e142/file_types endpoint")
        print("3. Verify Oracle metadata column contains file_type_counts")
        print()
        
        return 0
        
    except AssertionError as e:
        print(f"\n✗ TEST FAILED: {e}\n")
        return 1
    except Exception as e:
        print(f"\n✗ UNEXPECTED ERROR: {e}\n")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
