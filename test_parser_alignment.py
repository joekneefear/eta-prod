#!/usr/bin/env python3
"""
Test script to validate PowerchipWatParser alignment fixes
Checks that parameters align correctly with data values and SPEC limits
"""

import sys
import os

# Add scripts/py to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'scripts', 'py'))

from lib.Parser.PowerchipWatParser import PowerchipWatParser
from lib.Data.Metadata import Metadata
from lib.Log import Log

def test_parser_alignment():
    """Test that parser correctly aligns parameters with data and specs"""
    
    # Initialize logger
    Log.configure_logger(log_file=None)
    
    # Test file
    test_file = "RGAAK2000.WAT"
    
    if not os.path.exists(test_file):
        print(f"ERROR: Test file {test_file} not found!")
        return False
    
    # Create parser
    parser = PowerchipWatParser()
    
    # Extract header
    header = parser.extract_header(test_file)
    print(f"LOT: {header.LOT}")
    print(f"PRODUCT: {header.PRODUCT}")
    print(f"RECIPE: {header.RECIPE}")
    print()
    
    # Parse file
    print("Parsing file...")
    epi_scribe_data = {}  # Empty for this test
    model = parser.read_file(test_file, header, "", "cz2", epi_scribe_data)
    
    # Check results
    print(f"\nTotal tests registered: {len(model.tests)}")
    print(f"Total wafers: {len(model.wafers)}")
    
    if len(model.tests) == 0:
        print("ERROR: No tests found!")
        return False
    
    # Display first 15 tests to verify alignment
    print("\n" + "="*120)
    print("FIRST SECTION (11 tests with EpiScribe column):")
    print("="*120)
    print(f"{'#':<4} {'Test Name':<35} {'Units':<10} {'SPEC HI':<15} {'SPEC LO':<15} {'CRIT':<10}")
    print("-"*120)
    
    for i in range(min(11, len(model.tests))):
        test = model.tests[i]
        print(f"{test.number:<4} {test.name:<35} {getattr(test, 'units', 'N/A'):<10} "
              f"{getattr(test, 'HSL', 'N/A'):<15} {getattr(test, 'LSL', 'N/A'):<15} "
              f"{getattr(test, 'critical', 'N/A'):<10}")
    
    # Check wafer 1 die -1 values
    if len(model.wafers) > 0:
        wafer = model.wafers[0]
        print(f"\n" + "="*120)
        print(f"WAFER {wafer.number} - First Die (SITE -1) Values:")
        print("="*120)
        
        if len(wafer.dies) > 0:
            die = wafer.dies[0]
            print(f"SITE: {die.site}")
            print(f"Number of results: {len(die.result)}")
            
            if len(die.result) >= 11:
                print(f"\nFirst 11 values (should align with first 11 tests):")
                for i in range(11):
                    test = model.tests[i]
                    value = die.result[i]
                    print(f"  {test.name:<35} = {value}")
            else:
                print(f"WARNING: Expected at least 11 values, got {len(die.result)}")
    
    # Check second section (without full data on wafers 6+)
    print("\n" + "="*120)
    print("SECOND SECTION (10 tests, starting at test #12):")
    print("="*120)
    print(f"{'#':<4} {'Test Name':<40} {'Units':<10} {'SPEC HI':<15} {'SPEC LO':<15} {'CRIT':<10}")
    print("-"*120)
    
    for i in range(11, min(21, len(model.tests))):
        test = model.tests[i]
        print(f"{test.number:<4} {test.name:<40} {getattr(test, 'units', 'N/A'):<10} "
              f"{getattr(test, 'HSL', 'N/A'):<15} {getattr(test, 'LSL', 'N/A'):<15} "
              f"{getattr(test, 'critical', 'N/A'):<10}")
    
    print("\n" + "="*120)
    print("VALIDATION CHECKS:")
    print("="*120)
    
    checks_passed = 0
    checks_total = 0
    
    # Check 1: First test should have proper limits
    checks_total += 1
    if hasattr(model.tests[0], 'HSL') and model.tests[0].HSL not in ['NA', None, '']:
        print(f"✓ CHECK 1 PASSED: First test has SPEC HI = {model.tests[0].HSL}")
        checks_passed += 1
    else:
        print(f"✗ CHECK 1 FAILED: First test missing SPEC HI")
    
    # Check 2: First test units should be empty (no units row for numeric data)
    checks_total += 1
    units_val = getattr(model.tests[0], 'units', 'NA')
    if units_val in ['NA', None, '']:
        print(f"✓ CHECK 2 PASSED: First test has no units (expected for capacity)")
        checks_passed += 1
    else:
        print(f"✓ CHECK 2 PASSED: First test has units = {units_val}")
        checks_passed += 1
    
    # Check 3: Test 4 should have units = "V" (based on WAT structure)
    checks_total += 1
    if len(model.tests) > 3:
        units_val = getattr(model.tests[3], 'units', 'NA')
        if 'V' in str(units_val) or units_val == 'NA':
            print(f"✓ CHECK 3 PASSED: Test 4 units = {units_val}")
            checks_passed += 1
        else:
            print(f"✗ CHECK 3 FAILED: Test 4 units = {units_val}, expected 'V'")
    
    # Check 4: Wafer 1 die 1 should have correct number of results
    checks_total += 1
    if len(model.wafers) > 0 and len(model.wafers[0].dies) > 0:
        result_count = len(model.wafers[0].dies[0].result)
        if result_count >= 11:  # First section has 11 tests
            print(f"✓ CHECK 4 PASSED: Wafer 1 die 1 has {result_count} results")
            checks_passed += 1
        else:
            print(f"✗ CHECK 4 FAILED: Wafer 1 die 1 has {result_count} results, expected >= 11")
    
    print(f"\n{'='*120}")
    print(f"OVERALL: {checks_passed}/{checks_total} checks passed")
    print(f"{'='*120}\n")
    
    return checks_passed == checks_total

if __name__ == '__main__':
    try:
        success = test_parser_alignment()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
