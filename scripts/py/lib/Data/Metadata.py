"""
SYNOPSIS

DESCRIPTION
    Metadata class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Oct-12 - jgarcia - initial
    2025-Mar-11 - jgarcia - refactored to be similarly defined to Perl version
    2025-May-18 - jgarcia - made sure CREATION_DATE has value.

LICENSE
    (C) onsemi 2023 All rights reserved.
"""

from lib.Data.Base import Base
from lib.Log import Log
from lib.Util import Util

from datetime import datetime

class Metadata(Base):
    
    ATTRS = ["isFinalLot", "isRelLot", "ertUrl"]

    def __init__(self, args=None):
        """Initialize Metadata with formatted dates and default values."""
        args = args or {}  # Ensure args is a dictionary
        super().__init__(args)

        if args:
            for key, value in args.items():
                if key.endswith("TIME") or key.endswith("DATE"):
                    args[key] = self.format_date_to_yyyymmdd_hms(value)  # Format date attributes

        self.CREATION_DATE = self.current_date()
        args["CREATION_DATE"] = self.CREATION_DATE  # Ensure it's preserved
        # Initialize all attributes listed in the list method
        self.initialize_attributes(args)

    def array(self):
        """Defines attributes that should be treated as lists."""
        return []

    def list(self):
        return ['PROGRAM_CLASS', 'VERSION', 'CREATION_DATE', 'ALTERNATE_LOT', 'ALTERNATE_PRODUCT', 'AREA',
                'CABLE_ID', 'DATA_FILE_NAME', 'DATE_TIME_MASK', 'DEFAULT_MAPPING_VERSION', 'DEFAULT_MAPPING_DATE',
                'DUT_BOARD', 'END_TIME', 'FACILITY', 'FAMILY', 'HANDLER', 'LOAD_BOARD', 'LOAD_BOARD_TYPE',
                'LOT_TYPE', 'FAB', 'LOT', 'MASK_SET', 'MEASURING_EQUIPMENT', 'EQUIP1_ID', 'LOT_CLASS', 'ONS_LOT_CLASS', 'OPERATOR', 'PDS_FILE',
                'PROBE_CARD', 'PROBE_CARD_TYPE', 'PROGRAM', 'PROCESS', 'PROCESSING_STEP', 'PRODUCT', 'PRODUCT_CODE',
                'PTI_2', 'PTI_4_PAL', 'RECIPE', 'RECIPE_REVISION', 'RESULT_TIME', 'SCRIBE_ID', 'SLOT', 'SOURCE_LOT',
                'START_TIME', 'STEP', 'SUBCON_LOT', 'SUBCON_PRODUCT', 'TECHNOLOGY', 'TEMPERATURE', 'TESTER_HOST_NAME',
                'TESTER_ID', 'TESTER_SOFTWARE', 'TESTER_SOFTWARE_VERSION', 'TESTER_TYPE', 'TEST_FACILITY', 'TEST_FLOOR',
                'TEST_MODE', 'DATE_CODE', 'WMC_CENTER_X', 'WMC_CENTER_Y', 'WMC_DIE_HEIGHT', 'WMC_DIE_WIDTH',
                'WMC_FLAT_TYPE', 'WMC_POSITIVE_X', 'WMC_POSITIVE_Y', 'WMC_RETICLE_COL_OFFSET', 'WMC_RETICLE_COLS',
                'WMC_RETICLE_ROW_OFFSET', 'WMC_RETICLE_ROWS', 'WMC_WAFER_FLAT', 'WMC_WAFER_SIZE', 'WMC_WAFER_UNITS', 'RETEST_BIN']
    
    def initialize_attributes(self, args):
        """Initialize attributes listed in the list method while preserving existing values."""
        for attr in self.list():
            if not hasattr(self, attr) or getattr(self, attr) == "NA":
                setattr(self, attr, args.get(attr, "NA"))

    def format_date_to_yyyymmdd_hms(self, date_str):
        if date_str:
            try:
                return datetime.strptime(date_str, '%Y-%m-%d').strftime('%Y/%m/%d %H:%M:%S')
            except ValueError:
                return date_str
        return None

    def current_date(self):
        return datetime.now().strftime('%Y/%m/%d %H:%M:%S')

    def set(self, key, value):
        if key.endswith('TIME') or key.endswith('DATE'):
            value = self.format_date_to_yyyymmdd_hms(value)
        setattr(self, key, value)
    
    def populate_metadata(self):
        if not self.LOT:
            Log.ERROR("Lot to lookup RefDB is null")
            return False

        lookuptable = "PP_FINALLOT" if self.isFinalLot else "PP_LOT"
        hash_data = self.get_metadata_from_refdb(self.LOT, final_lot=self.isFinalLot)

        if hash_data:
            Log.INFO(f"Good. Meta Found for Lot = {self.LOT} in {lookuptable}")
            self.FAMILY = hash_data.get('family')
            self.PROCESS = hash_data.get('process')
            self.PRODUCT = hash_data.get('product') or hash_data.get('PRODUCT_ID') or self.PRODUCT
            self.PACKAGE = hash_data.get('package')
            self.FAB = hash_data.get('fab_desc') if hash_data.get('fab_desc') not in ["", "N/A", "NA"] else self.FAB
            self.ONS_LOT_CLASS = hash_data.get('lot_class')
            self.DATE_CODE = hash_data.get('date_code')
            self.SOURCE_LOT = Util.format_source_lot(hash_data.get('source_lot'), self.LOT)

            if hash_data.get('product_prod') or hash_data.get('PRODUCT_ID') or hash_data.get('fld_device'):
                return True
            else:
                Log.WARN("Product not available from metadata..sending to sandbox.")
                return False
        else:
            Log.WARN(f"Bad.. Meta Not Found for Lot = {self.LOT} in {lookuptable}")
            return False

    def get_metadata_from_refdb(self, lot, final_lot=False):
        # engine = create_engine('your_database_connection_string')
        # Session = sessionmaker(bind=engine)
        # session = Session()
        session = self.refdb.get_session()

        if final_lot:
            result = session.query(PpFinalLot).filter_by(LOT=lot).first()
        else:
            result = session.query(PpLot).filter_by(LOT=lot).first()

        if result:
            product_info = session.query(PpProd).filter_by(PRODUCT=result.PRODUCT).first()
            metadata = {
                'family': product_info.FAMILY if product_info else None,
                'process': product_info.PROCESS if product_info else None,
                'product': result.PRODUCT,
                'PRODUCT_ID': result.PRODUCT,
                'package': product_info.PACKAGE if product_info else None,
                'fab_desc': product_info.FAB_DESC if product_info else None,
                'lot_class': result.LOT_OWNER,
                'date_code': result.DATE_CODE,
                'source_lot': result.SOURCE_LOT,
                'product_prod': product_info.PRODUCT if product_info else None,
                'fld_device': product_info.ITEM_TYPE if product_info else None
            }
            return metadata
        else:
            return None
    
    def populate_metadata_ert(self, metadata_dict):
        if not self.LOT:
            Log.WARN("LOT is not initialized")
            return False

        if metadata_dict is None:
            Log.WARN("Metadata dictionary is not provided")
            return False

        if metadata_dict.get('onLot', {}).get('status') in ["NO_DATA", "ERROR"]:
            Log.INFO("metadata not found on REFDB.ON_LOT")
            return False
        elif metadata_dict.get('onLot', {}).get('status') == "FOUND":
            Log.INFO(f"Good. Meta Found for Lot = {self.LOT} on REFDB.ON_LOT")
            self.process_decoded_json_on_lot_prod(metadata_dict)
            return True

    def process_decoded_json_on_lot_prod(self, decoded_json):
        self.FAB = Util.rep_na(decoded_json.get('onLot', {}).get('fab'))
        self.SOURCE_LOT = Util.formatSourceLot(decoded_json.get('onLot', {}).get('sourceLot'), self.LOT)
        self.FAMILY = Util.rep_na(decoded_json.get('onProd', {}).get('family'))
        self.LOT_TYPE = Util.rep_na(decoded_json.get('onLot', {}).get('lotType'))
        self.ONS_LOT_CLASS = Util.rep_na(decoded_json.get('onLot', {}).get('lotClass'))
        self.PTI_4_PAL = Util.rep_na(decoded_json.get('onProd', {}).get('pti4'))
        self.TECHNOLOGY = Util.rep_na(decoded_json.get('onProd', {}).get('technology'))
        if not self.PRODUCT or self.PRODUCT in ["N/A", "NA"]:
            self.PRODUCT = Util.rep_na(decoded_json.get('onProd', {}).get('product'))
    