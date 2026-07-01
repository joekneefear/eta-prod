"""
SYNOPSIS
    Example integration script showing new parser components

DESCRIPTION
    Demonstrates usage of:
    - PowerchipWatParsingConfig for centralized configuration
    - PowerchipWatFileValidator for pre-validation
    - PowerchipWatGapDetector for refactored gap detection
    - PowerchipWatQualityGate for quality assessment

USAGE
    python integration_example.py RGAAK2000.WAT

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2026-Jan-15 - jgarcia - Initial example

LICENSE
    (C) onsemi 2026 All rights reserved.
"""
import sys
import os

# Add lib directory to path
sys.path.insert(0, os.path.dirname(__file__))

from lib.Config.PowerchipWatParsingConfig import PowerchipWatParsingConfig
from lib.Utility.PowerchipWatFileValidator import PowerchipWatFileValidator
from lib.Utility.PowerchipWatGapDetector import PowerchipWatGapDetector
from lib.Utility.PowerchipWatQualityGate import PowerchipWatQualityGate, ParseQuality


def main():
    """Main integration example."""
    if len(sys.argv) < 2:
        print("Usage: python integration_example.py <wat_file>")
        sys.exit(1)
    
    wat_file = sys.argv[1]
    
    print(f"\n{'='*70}")
    print(f"PowerchipWatParser - Integration Example")
    print(f"{'='*70}")
    print(f"File: {wat_file}\n")
    
    # Step 1: Configure parser with custom settings
    print("Step 1: Initialize configuration...")
    config = PowerchipWatParsingConfig({
        'LEADING_GAP_THRESHOLD_LARGE': 5,
        'MIN_QUALITY_THRESHOLD': 0.7,
        'STRICT_MODE': False,
        'PAD_TOKEN': 'NA'
    })
    config.validate()
    print("✅ Configuration validated")
    
    # Step 2: Validate file structure
    print("\nStep 2: Validate file structure...")
    try:
        with open(wat_file, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"❌ File not found: {wat_file}")
        sys.exit(1)
    
    validator = PowerchipWatFileValidator()
    is_valid, errors, warnings = validator.validate_file_structure(lines)
    
    if not is_valid:
        print(f"❌ Validation FAILED:")
        for error in errors:
            print(f"  ERROR: {error}")
        sys.exit(1)
    
    print(f"✅ File structure valid")
    if warnings:
        print(f"⚠️  {len(warnings)} warnings:")
        for warning in warnings[:5]:
            print(f"  - {warning}")
    
    # Step 3: Initialize quality gate
    print("\nStep 3: Initialize quality gate...")
    quality_gate = PowerchipWatQualityGate(config)
    quality_gate.start_report(wat_file)
    print("✅ Quality gate initialized")
    
    # Step 4: Parse sample rows with gap detection
    print("\nStep 4: Parse sample rows...")
    detector = PowerchipWatGapDetector(config)
    
    # Simulate parsing a few rows
    sample_rows = [
        ("                                     -12.35458  0.7366  1.234", 11, "06", "-1"),
        ("0.5  1.2  3.4  4.8  5.9  6.1  7.2  8.3  9.4  10.5  11.6", 11, "01", "+1"),
        ("       0.5                    1.2  3.4", 6, "03", "+2"),
    ]
    
    for idx, (row_data, expected, wafer, site) in enumerate(sample_rows, 1):
        print(f"\n  Row {idx}: Wafer {wafer}, Site {site}")
        
        # Parse with gap detection
        result = detector.insert_nas_for_gaps(row_data, expected)
        
        # Assess quality
        quality = quality_gate.assess_row_quality(
            row_number=idx,
            wafer=wafer,
            site=site,
            values=result,
            expected=expected,
            method_used="heuristic"
        )
        
        # Check quality
        is_ok, error_msg = quality_gate.check_quality(quality, row_data)
        
        print(f"    Values: {result[:5]}...")
        print(f"    Quality: {quality.quality_ratio:.1%} ({quality.valid_numeric_count}/{expected} valid)")
        
        if not is_ok:
            print(f"    ⚠️  {error_msg}")
        else:
            print(f"    ✅ Passed")
    
    # Step 5: Generate quality report
    print(f"\n{'='*70}")
    print("Step 5: Generate quality report...")
    report = quality_gate.finalize_report()
    print(report.summary())
    
    # Step 6: Summary
    print(f"{'='*70}")
    print("Integration Example Complete")
    print(f"{'='*70}")
    print(f"\nComponents demonstrated:")
    print(f"  ✅ PowerchipWatParsingConfig - Centralized configuration")
    print(f"  ✅ PowerchipWatFileValidator - Pre-validation checks")
    print(f"  ✅ PowerchipWatGapDetector - Refactored gap detection")
    print(f"  ✅ PowerchipWatQualityGate - Quality assessment framework")
    print(f"\nNext steps:")
    print(f"  1. Run test suite: pytest tests/test_powerchip_wat_parser.py -v")
    print(f"  2. Review README: cat README_PARSER_IMPROVEMENTS.md")
    print(f"  3. Integrate components into PowerchipWatParser.py")
    print()


if __name__ == '__main__':
    main()
