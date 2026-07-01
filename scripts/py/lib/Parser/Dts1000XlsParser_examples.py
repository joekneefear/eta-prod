"""
Example usage of Dts1000XlsParser

This script demonstrates both standard and custom parsing modes.
"""

from lib.Parser.Dts1k2kXlsParser import Dts1k2kXlsParser
from lib.Config.ParserConfig import ParserConfig
from lib.Parser.CustomExtractors import (
    LotIdExtractor,
    TestProgramExtractor,
    TimeExtractor
)


def example_standard_parsing():
    """Example: Standard parsing without custom extractors."""
    print("=" * 60)
    print("EXAMPLE 1: Standard Parsing")
    print("=" * 60)
    
    parser = Dts1k2kXlsParser()
    model = parser.parse_to_model('path/to/sample.xls')
    
    print(f"LOT: {model.header.LOT}")
    print(f"PRODUCT: {model.header.PRODUCT}")
    print(f"PROGRAM: {model.header.PROGRAM}")
    print(f"REVISION: {model.header.REVISION}")
    print(f"OPERATOR: {model.header.OPERATOR}")
    print(f"START_TIME: {model.header.START_TIME}")
    print(f"END_TIME: {model.header.END_TIME}")
    print(f"Number of tests: {len(model.tests)}")
    print(f"Number of dies: {len(model.wafers[0].dies)}")
    print(f"Number of bins: {len(model.wafers[0].bins)}")
    print()


def example_custom_lot_parsing():
    """Example: Custom lot ID parsing."""
    print("=" * 60)
    print("EXAMPLE 2: Custom Lot ID Parsing")
    print("=" * 60)
    print("Input lot format: FT-FCPF250N65S3L1-F154-HVPFT160003")
    print()
    
    config = ParserConfig()
    config.register_extractor('lot_parser', LotIdExtractor.extract)
    
    parser = Dts1k2kXlsParser(config)
    model = parser.parse_to_model('path/to/sample.xls')
    
    print(f"PROCESS: {model.header.PROCESS}")         # 'FT' (Final Test)
    print(f"PRODUCT: {model.header.PRODUCT}")         # 'FCPF250N65S3L1'
    print(f"INTERNAL_CONTROL: {model.header.INTERNAL_CONTROL}")  # 'F154'
    print(f"LOT: {model.header.LOT}")                 # 'HVPFT160003'
    print()


def example_custom_program_parsing():
    """Example: Custom test program parsing."""
    print("=" * 60)
    print("EXAMPLE 3: Custom Test Program Parsing")
    print("=" * 60)
    print("Input: TestFileName = C:\\Programs\\MyTestProg5.tst")
    print()
    
    config = ParserConfig()
    config.register_extractor('program_parser', TestProgramExtractor.extract)
    
    parser = Dts1k2kXlsParser(config)
    model = parser.parse_to_model('path/to/sample.xls')
    
    print(f"PROGRAM: {model.header.PROGRAM}")         # 'MyTestProg'
    print(f"REVISION: {model.header.REVISION}")       # '5'
    print()


def example_custom_time_parsing():
    """Example: File modification time extraction."""
    print("=" * 60)
    print("EXAMPLE 4: File Modification Time Extraction")
    print("=" * 60)
    print("Using file modified timestamp instead of 1/1/1970")
    print()
    
    config = ParserConfig()
    config.register_extractor('time_parser', TimeExtractor.extract)
    
    parser = Dts1k2kXlsParser(config)
    model = parser.parse_to_model('path/to/sample.xls')
    
    print(f"START_TIME: {model.header.START_TIME}")   # File modified time
    print(f"END_TIME: {model.header.END_TIME}")       # File modified time
    print()


def example_all_custom_extractors():
    """Example: All custom extractors combined."""
    print("=" * 60)
    print("EXAMPLE 5: All Custom Extractors Combined")
    print("=" * 60)
    
    config = ParserConfig()
    config.register_extractor('lot_parser', LotIdExtractor.extract)
    config.register_extractor('program_parser', TestProgramExtractor.extract)
    config.register_extractor('time_parser', TimeExtractor.extract)
    
    parser = Dts1k2kXlsParser(config)
    model = parser.parse_to_model('path/to/FT-FCPF250N65S3L1-F154-HVPFT160003.xls')
    
    print("Custom-parsed fields:")
    print(f"  PROCESS: {model.header.PROCESS}")
    print(f"  PRODUCT: {model.header.PRODUCT}")
    print(f"  INTERNAL_CONTROL: {model.header.INTERNAL_CONTROL}")
    print(f"  LOT: {model.header.LOT}")
    print(f"  PROGRAM: {model.header.PROGRAM}")
    print(f"  REVISION: {model.header.REVISION}")
    print(f"  START_TIME: {model.header.START_TIME}")
    print(f"  END_TIME: {model.header.END_TIME}")
    print()
    
    print("Standard fields:")
    print(f"  OPERATOR: {model.header.OPERATOR}")
    print(f"  EQUIP1_ID: {model.header.EQUIP1_ID}")
    print(f"  Number of tests: {len(model.tests)}")
    print(f"  Number of dies: {len(model.wafers[0].dies)}")
    print(f"  Number of bins: {len(model.wafers[0].bins)}")
    print()


if __name__ == '__main__':
    print("\n")
    print("*" * 60)
    print("DTS1000/DTS2000 XLS Parser - Usage Examples")
    print("*" * 60)
    print("\n")
    
    # Note: Replace 'path/to/sample.xls' with actual file path
    # Uncomment the examples you want to run:
    
    # example_standard_parsing()
    # example_custom_lot_parsing()
    # example_custom_program_parsing()
    # example_custom_time_parsing()
    # example_all_custom_extractors()
    
    print("To run examples, uncomment the function calls above and")
    print("replace 'path/to/sample.xls' with an actual DTS1000/DTS2000 Excel file.")
