
import sys
import os
import re

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from lib.Parser.PowerchipWatParser import PowerchipWatParser
from lib.Data.Model import Model

def test_fixed_anchor_parsing():
    print("Starting verification test...")
    wat_file = r'c:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\RGAAK2000.WAT'
    parser = PowerchipWatParser()
    model = Model()
    
    # Read the file
    parser.read_file(wat_file, model)
    
    # Debug info
    print(f"Total tests: {len(model.tests)}")
    
    # 1. Verify parameter names are extracted correctly
    # CAPDENSITY_MIMLACAP_0P0 should be the first param
    first_test = model.tests[0]
    print(f"First test: {first_test.name}")
    assert first_test.name == 'CAPDENSITY_MIMLACAP_0P0'
    
    # 2. Verify units extraction (ID ID line)
    # CAPDENSITY_MIMLACAP_0P0 units are empty (NA)
    # MIMLACAP_ILK is index 3 or so... let's check its name
    print(f"Units for {first_test.name}: '{first_test.units}'")
    
    # Search for MIMLACAP_ILK
    mim_test = next((t for t in model.tests if t.name == 'MIMLACAP_ILK'), None)
    if mim_test:
        print(f"Units for {mim_test.name}: '{mim_test.units}'")
        assert mim_test.units == 'Volts'
    
    # 3. Verify data values for first wafer/site
    # WAF: 01, SITE: -1
    # Line 8: row[28:43] should be 0.9681541
    results = model.get_wafer_test_results('01', -1)
    if results:
        val0 = results[0].value
        print(f"Value for {model.tests[0].name} at WAF 01 SITE -1: {val0}")
        assert val0 == '0.9681541'
    else:
        print("No results found for WAF 01 SITE -1")
        assert False

if __name__ == '__main__':
    try:
        test_fixed_anchor_parsing()
        print("\nVerification SUCCESSFUL!")
    except Exception as e:
        print(f"\nVerification FAILED: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
