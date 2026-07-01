
"""
SYNOPSIS

DESCRIPTION
    MetadataDTO class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sept-03 - jgarcia - initial

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

from collections import OrderedDict
from xml.etree.ElementTree import Element, SubElement, tostring
from lib.Data.MetadataDTOAttribute import MetadataDTOAttribute
from lib.Log import Log
import xml.dom.minidom  # Importing the minidom module for pretty printing
from collections import OrderedDict


class MetadataDTO:
    ALTERNATE_LOT = "AlternateLot"
    ALTERNATE_PRODUCT = "AlternateProduct"
    AREA = "Area"
    CABLE_ID = "CableId"
    DATA_FILE_NAME = "DataFileName"
    DATE_TIME_MASK = "DateTimeMask"
    DEFAULT_MAPPING_VERSION = "DefaultMappingVersion"
    DEFAULT_MAPPING_DATE = "DefaultMappingDate"
    DUT_BOARD = "DutBoard"
    END_TIME = "EndTime"
    FACILITY = "Facility"
    FAMILY = "Family"
    HANDLER = "Handler"
    LOAD_BOARD = "LoadBoard"
    LOAD_BOARD_TYPE = "LoadBoardType"
    LOT_TYPE = "LotType"
    FAB = "Fab"
    LOT_ID = "LotId"
    MASK_SET = "MaskSet"
    MEASURING_EQUIPMENT = "MeasuringEquipment"
    ONS_LOT_CLASS = "ONSLotClass"
    OPERATOR = "Operator"
    PDS_FILE = "PdsFile"
    PROBE_CARD = "ProbeCard"
    PROBE_CARD_TYPE = "ProbeCardType"
    PROBE_PROGRAM_NAME = "ProbeProgramName"
    PROCESS = "Process"
    PROCESSING_STEP = "ProcessingStep"
    PRODUCT = "Product"
    PRODUCT_CODE = "ProductCode"
    PTI_2 = "Pti2"
    PTI_4_PAL = "Pti4Pal"
    RECIPE = "Recipe"
    RECIPE_REVISION = "RecipeRevision"
    RESULT_TIME = "ResultTime"
    SCRIBE_ID = "ScribeId"
    SLOT = "Slot"
    SOURCE_LOT = "SourceLot"
    START_TIME = "StartTime"
    STEP = "Step"
    SUBCON_LOT_ID = "SubconLotId"
    SUBCON_PRODUCT = "SubconProduct"
    TECHNOLOGY = "Technology"
    TEMPERATURE = "Temperature"
    TESTER_HOST_NAME = "TesterHostName"
    TESTER_ID = "TesterId"
    TESTER_SOFTWARE = "TesterSoftware"
    TESTER_SOFTWARE_VERSION = "TesterSoftwareVersion"
    TESTER_TYPE = "TesterType"
    TEST_FACILITY = "TestFacility"
    TEST_FLOOR = "TestFloor"
    TEST_MODE = "TestMode"
    WAFER_ID = "WaferId"
    WAFER_NUMBER = "WaferNumber"
    WMC_CENTER_X = "WmcCenterX"
    WMC_CENTER_Y = "WmcCenterY"
    WMC_DIE_HEIGHT = "WmcDieHeight"
    WMC_DIE_WIDTH = "WmcDieWidth"
    WMC_FLAT_TYPE = "WmcFlatType"
    WMC_POSITIVE_X = "WmcPositiveX"
    WMC_POSITIVE_Y = "WmcPositiveY"
    WMC_RETICLE_COL_OFFSET = "WmcReticleColOffset"
    WMC_RETICLE_COLS = "WmcReticleCols"
    WMC_RETICLE_ROW_OFFSET = "WmcReticleRowOffset"
    WMC_RETICLE_ROWS = "WmcReticleRows"
    WMC_WAFER_FLAT = "WmcWaferFlat"
    WMC_WAFER_SIZE = "WmcWaferSize"
    WMC_WAFER_UNITS = "WmcWaferUnits"
    WMC_CFG = "WmcConfigId"

    def __init__(self, api_client=None, ws_url=None, stdml_info=None, field_mapping=None, source_mapping=None):
        self.attributes = OrderedDict()
        self.api_client = api_client
        self.ws_url = ws_url
        self.stdml_info = stdml_info
        self.field_mapping = field_mapping if field_mapping is not None else {}  # Initialize field_mapping
        self.source_mapping = source_mapping if source_mapping is not None else {}  # Initialize field_mapping

    def get_metadata_self_attributes_as_list(self):
        return list(self.attributes.values())

    def get_metadata_self_attributes(self):
        return self.attributes

    def get_metadata_self_attribute(self, key):
        return self.attributes.get(key)

    def get_metadata_self_attribute_value(self, key):
        attribute = self.get_metadata_self_attribute(key)
        return attribute.value if attribute else None

    def set_metadata_self_attribute(self, key, attribute):
        self.attributes[key] = attribute

    def set_metadata_self_attribute_change_only_if_destination_is_null(self, key, source, value):
        if self.is_metadata_self_attribute_empty(key):
            self.set_metadata_self_attribute(key, MetadataDTOAttribute(key, source, value))

    def set_metadata_self_attribute(self, key, source=None, value=None):
        if value is None or (isinstance(value, str) and value.strip() == ""):
            self.attributes.pop(key, None)
            return

        attribute = self.attributes.get(key, MetadataDTOAttribute(key))
        if source is not None:
            attribute.source = source
        attribute.value = value
        self.attributes[key] = attribute

    def is_metadata_self_attribute_empty(self, key):
        attribute = self.get_metadata_self_attribute(key)
        return attribute is None or attribute.value.strip() == ""

    def __str__(self):
        return f"MetadataDTO(attributes={self.attributes})"

    def to_self_string(self):
        return "MetadataDTO{" + ", ".join(f"{attr.name}='{attr.value}'" for attr in self.attributes.values()) + "}"

    def clone(self):
        metadata_self_copy = MetadataDTO()
        for key, attribute in self.attributes.items():
            metadata_self_copy.attributes[key] = attribute.clone()
        return metadata_self_copy

    def generate_metadata_xml(self, data):
        from lib.Util import Util
        # Initialize attributes based on the provided data and sources
        self.initialize_all_attributes(data)

        # Define the order of attributes as declared in the class
        attribute_order = [
            self.ALTERNATE_LOT,
            self.ALTERNATE_PRODUCT,
            self.AREA,
            self.CABLE_ID,
            self.DATA_FILE_NAME,
            self.DATE_TIME_MASK,
            self.DEFAULT_MAPPING_VERSION,
            self.DEFAULT_MAPPING_DATE,  
            self.DUT_BOARD,
            self.END_TIME,
            self.FACILITY,
            self.FAMILY,
            self.HANDLER,
            self.LOAD_BOARD,
            self.LOAD_BOARD_TYPE,
            self.LOT_TYPE,
            self.FAB,
            self.LOT_ID,
            self.MASK_SET,
            self.MEASURING_EQUIPMENT,
            self.ONS_LOT_CLASS,
            self.OPERATOR,
            self.PDS_FILE,
            self.PROBE_CARD,
            self.PROBE_CARD_TYPE,
            self.PROBE_PROGRAM_NAME,
            self.PROCESS,
            self.PROCESSING_STEP,
            self.PRODUCT,
            self.PRODUCT_CODE,
            self.PTI_2,
            self.PTI_4_PAL,
            self.RECIPE,
            self.RECIPE_REVISION,
            self.RESULT_TIME,
            self.SCRIBE_ID,
            self.SLOT,
            self.SOURCE_LOT,
            self.START_TIME,
            self.STEP,
            self.SUBCON_LOT_ID,
            self.SUBCON_PRODUCT,
            self.TECHNOLOGY,
            self.TEMPERATURE,
            self.TESTER_HOST_NAME,
            self.TESTER_ID,
            self.TESTER_SOFTWARE,
            self.TESTER_SOFTWARE_VERSION,
            self.TESTER_TYPE,
            self.TEST_FACILITY,
            self.TEST_FLOOR,
            self.TEST_MODE,
            self.WAFER_ID,
            self.WAFER_NUMBER,
            self.WMC_CENTER_X,
            self.WMC_CENTER_Y,
            self.WMC_DIE_HEIGHT,
            self.WMC_DIE_WIDTH,
            self.WMC_FLAT_TYPE,
            self.WMC_POSITIVE_X,
            self.WMC_POSITIVE_Y,
            self.WMC_RETICLE_COL_OFFSET,
            self.WMC_RETICLE_COLS,
            self.WMC_RETICLE_ROW_OFFSET,
            self.WMC_RETICLE_ROWS,
            self.WMC_WAFER_FLAT,
            self.WMC_WAFER_SIZE,
            self.WMC_WAFER_UNITS,
            self.WMC_CFG
        ]

        # Manually construct the XML string
        xml_content = '<Metadata>\n'
        for attribute_name in attribute_order:
            if attribute_name in self.attributes:
                attribute = self.attributes[attribute_name]
                if attribute.name == "WaferNumber":
                    try:
                        if int(attribute.value) < 10: 
                            value = attribute.value.zfill(2)
                        else:
                            value = attribute.value
                    except (ValueError, TypeError):
                        Log.ERROR(f"Invalid wafer number detected: The provided wafer number is not recognized as a numerical value.->{attribute.value}")
                        Util.dp_exit(1,"Invalid wafer number detected: The provided wafer number is not recognized as a numerical value.")
                else:
                    value = attribute.value
                
                source = attribute.source if attribute.source else "UNKNOWN"
                # Manually create the opening and closing tags
                xml_content += f'    <Attribute Name="{attribute_name}" Source="{source}" Value="{value}"></Attribute>\n'
        xml_content += '</Metadata>'

        return xml_content

    def initialize_all_attributes(self, data, sources=None):
        self.convert_field_mapping_to_format()


        for section, mappings in self.field_mapping.items():
            if section in data:
                for key, field in mappings.items():
                    if key in data[section]:
                        source = self.source_mapping[section].get(key) if self.source_mapping and section in self.source_mapping and key in self.source_mapping[section] else None
                        self.set_metadata_self_attribute(field, source=source, value=data[section][key])

    def set_metadata_self_attribute(self, key, source=None, value=None):
        if value is None or (isinstance(value, str) and value.strip() == ""):
            self.attributes.pop(key, None)
            return

        attribute = self.attributes.get(key, MetadataDTOAttribute(key))
        if source is not None:
            attribute.source = source
        attribute.value = value
        self.attributes[key] = attribute

    def convert_field_mapping_to_format(self):
        # Initialize the new format
        new_format = {}
        
        # Iterate through the existing field mapping
        for section, mappings in self.field_mapping.items():
            new_format[section] = {key: getattr(self, value) for key, value in mappings.items()}
        
        self.field_mapping = new_format
    #    return new_format

# Call this function where needed
# Example usage:
# converted_mapping = self.convert_field_mapping_to_format()