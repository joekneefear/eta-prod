import os
import sys

# Mock log and config since we don't want to depend on the whole environment
class MockLog:
    def INFO(self, msg): print(f"INFO: {msg}")
    def WARN(self, msg): print(f"WARN: {msg}")
    def ERROR(self, msg): print(f"ERROR: {msg}")

class MockConfig:
    def has_extractor(self, name): return False
    def get_extractor(self, name): return None

# Mock Util.dp_exit
import lib.Util as Util
Util.dp_exit = lambda code, **kwargs: print(f"DP_EXIT called with code {code}, kwargs: {kwargs}")

# Add path to find the parser
sys.path.append(os.getcwd())

from scripts.py.lib.Parser.Dts1k2kXlsParser import Dts1k2kXlsParser


def test_encoding_fallback():
    test_file = "test_encoding.csv"
    # Case 1: Encoding Issue (0xa1)
    # Content: "PartID,Bin,Test\n1,1,Value\xa1"
    content_encoding = b"PartID,Bin,Test\n1,1,Value\xa1"
    
    # Case 2: Jagged CSV (ParserError)
    # Content:
    # Col1,Col2,Col3
    # 1,2,3
    # 1,2,3,4  <-- Extra column
    content_jagged = b"Col1,Col2,Col3\n1,2,3\n1,2,3,4"
    
    parser = Dts1k2kXlsParser()
    parser.logger = MockLog()
    
    try:
        print("\n--- Test Case 1: Encoding Issue (0xa1) ---")
        with open(test_file, "wb") as f:
            f.write(content_encoding)
        
        row_gen, count = parser._load_csv(test_file)
        rows = list(row_gen)
        print(f"Successfully loaded {count} rows")
        
        print("\n--- Test Case 2: Jagged CSV (ParserError) ---")
        with open(test_file, "wb") as f:
            f.write(content_jagged)
            
        row_gen, count = parser._load_csv(test_file)
        rows = list(row_gen)
        print(f"Successfully loaded {count} rows (jagged file)")
        for i, row in enumerate(rows):
            print(f"Row {i}: {row}")

    except Exception as e:
        print(f"FAILED: {e}")
        import traceback
        traceback.print_exc()
    finally:
        if os.path.exists(test_file):
            os.remove(test_file)

if __name__ == "__main__":
    test_encoding_fallback()
