"""
SYNOPSIS
    Unit tests for PowerchipWatParser and related components

DESCRIPTION
    Comprehensive test suite covering:
    - Gap detection (leading, middle, trailing)
    - Configuration management
    - File validation
    - Edge cases and error handling

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2026-Jan-15 - jgarcia - Initial test suite

LICENSE
    (C) onsemi 2026 All rights reserved.

USAGE
    Run with pytest:
        cd C:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\scripts\py
        pytest tests/test_powerchip_wat_parser.py -v
    
    Run specific test:
        pytest tests/test_powerchip_wat_parser.py::test_leading_gap_detection -v
    
    Run with coverage:
        pytest tests/test_powerchip_wat_parser.py --cov=lib.Parser --cov-report=html
"""
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pytest
from lib.Config.PowerchipWatParsingConfig import PowerchipWatParsingConfig
from lib.Utility.PowerchipWatGapDetector import PowerchipWatGapDetector
from lib.Utility.PowerchipWatFileValidator import PowerchipWatFileValidator


class TestParsingConfig:
    """Test configuration management."""
    
    def test_default_config(self):
        """Test default configuration values."""
        config = PowerchipWatParsingConfig()
        assert config.LEADING_GAP_THRESHOLD_LARGE == 5
        assert config.LEADING_GAP_THRESHOLD_MEDIUM == 3
        assert config.PAD_TOKEN == "NA"
        assert config.FIXED_WIDTH_FIELD_SIZE == 15
    
    def test_config_overrides(self):
        """Test configuration overrides."""
        config = PowerchipWatParsingConfig({
            'LEADING_GAP_THRESHOLD_LARGE': 10,
            'PAD_TOKEN': 'MISSING'
        })
        assert config.LEADING_GAP_THRESHOLD_LARGE == 10
        assert config.PAD_TOKEN == 'MISSING'
        assert config.FIXED_WIDTH_FIELD_SIZE == 15  # unchanged
    
    def test_config_from_args(self):
        """Test creating config from args dictionary."""
        args = {
            'pad_token': 'NULL',
            'fixed_width_enabled': False,
            'site_sign_mode': 'signed'
        }
        config = ParsingConfig.from_args(args)
        assert config.PAD_TOKEN == 'NULL'
        assert config.FIXED_WIDTH_ENABLED is False
        assert config.SITE_SIGN_MODE == 'signed'
    
    def test_config_validation(self):
        """Test configuration validation."""
        config = PowerchipWatParsingConfig()
        assert config.validate() is True
        
        # Test invalid configuration
        config.LEADING_GAP_THRESHOLD_LARGE = -5
        with pytest.raises(ValueError, match="must be >= 0"):
            config.validate()
    
    def test_config_to_dict(self):
        """Test configuration export to dictionary."""
        config = PowerchipWatParsingConfig()
        config_dict = config.to_dict()
        assert 'LEADING_GAP_THRESHOLD_LARGE' in config_dict
        assert 'PAD_TOKEN' in config_dict
        assert config_dict['FIXED_WIDTH_FIELD_SIZE'] == 15


class TestGapDetector:
    """Test gap detection logic."""
    
    @pytest.fixture
    def detector(self):
        """Create gap detector with default config."""
        config = PowerchipWatParsingConfig()
        return PowerchipWatGapDetector(config)
    
    def test_extract_tokens_with_positions(self, detector):
        """Test token extraction with positions."""
        text = "  -12.35458  0.7366  1.234  "
        tokens = detector.extract_tokens_with_positions(text)
        
        assert len(tokens) == 3
        assert tokens[0] == ("-12.35458", 2, 11)
        assert tokens[1] == ("0.7366", 13, 19)
        assert tokens[2] == ("1.234", 21, 26)
    
    def test_leading_gap_detection_large(self, detector):
        """Test detection of large leading gap (>5 chars)."""
        # Wafer 6 format: 50 chars leading space before first value
        row = "                                     -12.35458  0.7366  1.234"
        result = detector.insert_nas_for_gaps(row, 11)
        
        # First value should be NA due to leading gap
        assert result[0] == "NA"
        assert result[1] == "-12.35458"
        assert result[2] == "0.7366"
        assert result[3] == "1.234"
    
    def test_leading_gap_detection_medium_with_deficit(self, detector):
        """Test detection of medium leading gap (3-5 chars) with token deficit."""
        # 4 chars leading space, 2 tokens but 3 expected
        row = "    0.5  1.2"
        result = detector.insert_nas_for_gaps(row, 3)
        
        assert result[0] == "NA"
        assert result[1] == "0.5"
        assert result[2] == "1.2"
    
    def test_no_leading_gap_without_deficit(self, detector):
        """Test that small leading gap without deficit is not treated as gap."""
        # 4 chars leading space but enough tokens
        row = "    0.5  1.2  3.4"
        result = detector.insert_nas_for_gaps(row, 3)
        
        # Should use all tokens normally
        assert result[0] == "0.5"
        assert result[1] == "1.2"
        assert result[2] == "3.4"
    
    def test_middle_gap_detection(self, detector):
        """Test detection of middle gaps between tokens."""
        # Large gap between first and second token
        row = "0.5                    1.2  3.4"
        result = detector.insert_nas_for_gaps(row, 4)
        
        assert result[0] == "0.5"
        assert result[1] == "NA"  # middle gap detected
        assert result[2] == "1.2"
        assert result[3] == "3.4"
    
    def test_trailing_blank_padding(self, detector):
        """Test padding of trailing blank columns."""
        row = "0.5  1.2"
        result = detector.insert_nas_for_gaps(row, 5)
        
        assert result[0] == "0.5"
        assert result[1] == "1.2"
        assert result[2] == "NA"  # trailing padding
        assert result[3] == "NA"
        assert result[4] == "NA"
    
    def test_all_na_row(self, detector):
        """Test handling of completely empty row."""
        row = ""
        result = detector.insert_nas_for_gaps(row, 3)
        
        assert result == ["NA", "NA", "NA"]
    
    def test_single_column(self, detector):
        """Test parsing with single column expected."""
        row = "  42.5  "
        result = detector.insert_nas_for_gaps(row, 1)
        
        assert result == ["42.5"]
    
    def test_exact_token_count(self, detector):
        """Test row with exact number of tokens (no gaps)."""
        row = "0.5  1.2  3.4  4.8  5.9"
        result = detector.insert_nas_for_gaps(row, 5)
        
        assert result == ["0.5", "1.2", "3.4", "4.8", "5.9"]
    
    def test_scientific_notation(self, detector):
        """Test handling of scientific notation values."""
        row = "2.5e-05  -0.08664463  1.234E+10"
        result = detector.insert_nas_for_gaps(row, 3)
        
        assert result[0] == "2.5e-05"
        assert result[1] == "-0.08664463"
        assert result[2] == "1.234E+10"
    
    def test_adaptive_threshold_computation(self, detector):
        """Test adaptive threshold calculation."""
        tokens_spans = [
            ("val1", 0, 4),
            ("val2", 6, 10),
            ("val3", 12, 16)
        ]
        threshold = detector.compute_adaptive_threshold(tokens_spans, 0)
        
        # Threshold should be reasonable based on gaps (2 chars between tokens)
        assert threshold >= 3  # minimum threshold
        assert threshold < 10  # should not be too large
    
    def test_should_use_gap_detection_with_deficit(self, detector):
        """Test gap detection decision with token deficit."""
        tokens_spans = [("val", 0, 3), ("val", 5, 8)]
        needs_gap, deficit, threshold, first_gap = detector.should_use_gap_detection(
            tokens_spans, 5
        )
        
        assert needs_gap is True
        assert deficit == 3  # 5 expected - 2 actual
    
    def test_should_use_gap_detection_no_gaps(self, detector):
        """Test gap detection decision with no gaps."""
        tokens_spans = [("val", 0, 3), ("val", 4, 7), ("val", 8, 11)]
        needs_gap, deficit, threshold, first_gap = detector.should_use_gap_detection(
            tokens_spans, 3
        )
        
        # Should not need gap detection - exact tokens, no deficit
        assert needs_gap is False
        assert deficit == 0


class TestFileValidator:
    """Test file structure validation."""
    
    @pytest.fixture
    def validator(self):
        """Create file validator."""
        return PowerchipWatFileValidator()
    
    def test_empty_file(self, validator):
        """Test validation of empty file."""
        lines = []
        is_valid, errors, warnings = validator.validate_file_structure(lines)
        
        assert is_valid is False
        assert "empty" in errors[0].lower()
    
    def test_short_file(self, validator):
        """Test validation of too-short file."""
        lines = ["line1", "line2", "line3"]
        is_valid, errors, warnings = validator.validate_file_structure(lines)
        
        assert is_valid is False
        assert "too short" in errors[0].lower()
    
    def test_missing_lot_header(self, validator):
        """Test detection of missing LOT ID header."""
        lines = ["header line"] * 20
        is_valid, errors, warnings = validator.validate_file_structure(lines)
        
        assert is_valid is False
        assert any("LOT ID" in error for error in errors)
    
    def test_missing_parameter_header(self, validator):
        """Test detection of missing parameter header."""
        lines = [
            "LOT ID : TEST123",
            "VERSION : 1.0",
            "TESTER TYPE : HP"
        ] + ["data line"] * 20
        is_valid, errors, warnings = validator.validate_file_structure(lines)
        
        assert is_valid is False
        assert any("parameter header" in error.lower() for error in errors)
    
    def test_valid_file_structure(self, validator):
        """Test validation of properly structured file."""
        lines = [
            "TYPE NO : T123  PROCESS  : P456  PCM SPEC: S789  QTY: 25  pcs",
            "LOT ID : TESTLOT  DATE : 2025/01/15  TIME : 10:30:00  Program NAME : TEST",
            "VERSION : 1.0  TESTER TYPE : HP  TESTER ID : T001  PRODUCT ID : PROD123",
            "",
            "WAF  SITE  PARAM1  PARAM2  PARAM3",
            "ID  ID  units1  units2  units3",
            "SPEC HI  10  20  30",
            "SPEC LO  -10  -20  -30",
            "1  +1  0.5  1.2  3.4",
            "1  +2  0.6  1.3  3.5",
            "2  +1  0.7  1.4  3.6",
            "2  +2  0.8  1.5  3.7",
            "3  +1  0.9  1.6  3.8"
        ]
        is_valid, errors, warnings = validator.validate_file_structure(lines)
        
        assert is_valid is True
        assert len(errors) == 0
    
    def test_warnings_for_missing_optional_sections(self, validator):
        """Test that missing optional sections generate warnings."""
        lines = [
            "LOT ID : TESTLOT  DATE : 2025/01/15  TIME : 10:30:00  Program NAME : TEST",
            "WAF  SITE  PARAM1  PARAM2  PARAM3",
            "1  +1  0.5  1.2  3.4"
        ] + ["filler"] * 20
        
        is_valid, errors, warnings = validator.validate_file_structure(lines)
        
        # Should pass validation but have warnings
        assert is_valid is True  # No errors
        assert len(warnings) > 0
        assert any("UNITS" in w or "SPEC" in w for w in warnings)


class TestIntegration:
    """Integration tests for full parsing workflow."""
    
    def test_wafer_6_format_end_to_end(self):
        """Test end-to-end parsing of wafer 6 format (leading blanks)."""
        config = PowerchipWatParsingConfig()
        detector = PowerchipWatGapDetector(config)
        
        # Simulate wafer 6 row: 3 leading blank columns, then values
        row = "                                     -12.35458  0.7366  1.234  2.456  3.789"
        result = detector.insert_nas_for_gaps(row, 11)
        
        # Verify first 3 columns are NA (leading blanks)
        assert result[0] == "NA"
        assert result[1] == "NA"
        assert result[2] == "NA"
        
        # Verify actual values start at column 3
        assert result[3] == "-12.35458"
        assert result[4] == "0.7366"
        assert result[5] == "1.234"
        
        # Verify trailing NAs
        assert result[10] == "NA"
    
    def test_normal_format_end_to_end(self):
        """Test end-to-end parsing of normal format (no leading blanks)."""
        config = PowerchipWatParsingConfig()
        detector = PowerchipWatGapDetector(config)
        
        # Normal row: all values present
        row = "0.5  1.2  3.4  4.8  5.9  6.1  7.2  8.3  9.4  10.5  11.6"
        result = detector.insert_nas_for_gaps(row, 11)
        
        # All values should be parsed correctly
        assert result[0] == "0.5"
        assert result[5] == "6.1"
        assert result[10] == "11.6"
        assert "NA" not in result
    
    def test_mixed_gaps_format(self):
        """Test parsing with both leading and middle gaps."""
        config = PowerchipWatParsingConfig()
        detector = PowerchipWatGapDetector(config)
        
        # Leading gap + middle gap
        row = "       0.5                    1.2  3.4"
        result = detector.insert_nas_for_gaps(row, 6)
        
        # Should detect leading gap and middle gap
        assert result[0] == "NA"  # leading
        assert result[1] == "0.5"
        assert result[2] == "NA"  # middle gap
        assert result[3] == "1.2"
        assert result[4] == "3.4"
        assert result[5] == "NA"  # trailing


class TestEdgeCases:
    """Test edge cases and error conditions."""
    
    def test_zero_expected_columns(self):
        """Test handling of zero expected columns."""
        config = PowerchipWatParsingConfig()
        detector = PowerchipWatGapDetector(config)
        
        row = "0.5  1.2  3.4"
        result = detector.insert_nas_for_gaps(row, 0)
        
        # Should return tokens as-is when expected=0
        assert len(result) == 3
    
    def test_negative_expected_columns(self):
        """Test handling of negative expected columns."""
        config = PowerchipWatParsingConfig()
        detector = PowerchipWatGapDetector(config)
        
        row = "0.5  1.2"
        result = detector.insert_nas_for_gaps(row, -5)
        
        # Should handle gracefully
        assert isinstance(result, list)
    
    def test_very_large_gaps(self):
        """Test handling of extremely large gaps."""
        config = PowerchipWatParsingConfig()
        detector = PowerchipWatGapDetector(config)
        
        row = "0.5" + (" " * 100) + "1.2"
        result = detector.insert_nas_for_gaps(row, 5)
        
        # Should detect gap despite large size
        assert result[0] == "0.5"
        assert result[1] == "NA"
        assert "1.2" in result
    
    def test_unicode_minus_signs(self):
        """Test handling of Unicode minus characters."""
        config = PowerchipWatParsingConfig()
        detector = PowerchipWatGapDetector(config)
        
        # Use actual Unicode minus (U+2212)
        row = "0.5  \u22121.2  3.4"
        tokens = detector.extract_tokens_with_positions(row)
        
        # Should extract tokens including Unicode minus
        assert len(tokens) == 3
        assert tokens[1][0] == "\u22121.2"


if __name__ == '__main__':
    pytest.main([__file__, '-v', '--tb=short'])
