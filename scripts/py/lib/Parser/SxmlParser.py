"""
SYNOPSIS

DESCRIPTION
    SxmlParser

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Sep-06 - jgarcia - initial

LICENSE
    (C) onsemi 2023 All rights reserved.
"""

import xml.etree.ElementTree as ET
import gzip
import re
from io import BytesIO
from lib.Util import Util
from lib.Log import Log
from lib.Data.MetadataDTO import MetadataDTO
from lib.Data.Model import Model
from lib.Data.Wafer import Wafer
from lib.Data.Die import Die

class SxmlParser:

    def __init__(self, xml_data, pplogger=None, sanitizer_config=None):
        self.pplogger = pplogger
        self.xml_content = None
        self.root = None
        self.is_malformed = False
        self.sanitizer_config = sanitizer_config if isinstance(sanitizer_config, dict) else {}
        
        try:
            if xml_data.endswith('.gz'):
                # Data is compressed, decompress it
                with gzip.open(xml_data, 'rb') as f:
                    decompressed_data = f.read()
                # Decode the decompressed data to a string
                xml_content = decompressed_data.decode('utf-8')
            else:
                # Data is not compressed
                with open(xml_data, 'r', encoding='utf-8') as f:
                    xml_content = f.read()
            
            # Store the original content
            self.xml_content = xml_content
            
            # Try to parse the XML content
            try:
                self.root = ET.fromstring(xml_content)
                Log.INFO("XML parsed successfully")
            except ET.ParseError as parse_error:
                Log.WARN(f"Initial XML parse failed: {parse_error}")
                
                # Try to identify the problematic area
                error_line, error_col = self._extract_error_location(str(parse_error))
                if error_line and error_col:
                    self._log_error_context(xml_content, error_line, error_col)
                
                Log.INFO("Attempting to sanitize and re-parse XML...")
                
                # Attempt to sanitize the XML
                sanitized_content = self._sanitize_xml(xml_content)
                
                try:
                    self.root = ET.fromstring(sanitized_content)
                    self.xml_content = sanitized_content
                    self.is_malformed = True
                    Log.INFO("XML successfully parsed after sanitization")
                except ET.ParseError as sanitize_error:
                    Log.ERROR(f"Failed to parse XML even after sanitization: {sanitize_error}")
                    
                    # Try to identify the problematic area in sanitized content
                    error_line, error_col = self._extract_error_location(str(sanitize_error))
                    if error_line and error_col:
                        self._log_error_context(sanitized_content, error_line, error_col)
                    
                    Log.WARN("Attempting fallback: extracting data using regex patterns...")
                    
                    # Use fallback extraction method
                    self.root = self._create_minimal_tree_from_regex(xml_content)
                    self.is_malformed = True
                    
                    if self.root is None:
                        Log.ERROR("All parsing attempts failed")
                        Util.dp_exit(1, pplogger=self.pplogger, error=f"Failed to parse XML: {parse_error}")
                    else:
                        Log.INFO("Fallback extraction successful - continuing with partial data")
                        
        except Exception as e:
            Log.ERROR(f"Error reading file: {e}")
            self.root = None
            Util.dp_exit(1, pplogger=self.pplogger, error=f"Error reading file: {e}")
    
    def _extract_error_location(self, error_message):
        """
        Extract line and column numbers from XML parse error message.
        Returns (line, column) tuple or (None, None) if not found.
        """
        match = re.search(r'line (\d+), column (\d+)', error_message)
        if match:
            return int(match.group(1)), int(match.group(2))
        return None, None
    
    def _log_error_context(self, xml_content, error_line, error_col):
        """
        Log the context around the XML parsing error for debugging.
        """
        lines = xml_content.split('\n')
        
        if error_line <= len(lines):
            # Get the problematic line (1-indexed to 0-indexed)
            problem_line = lines[error_line - 1] if error_line > 0 else ""
            
            # Log context: 2 lines before and after
            start_line = max(0, error_line - 3)
            end_line = min(len(lines), error_line + 2)
            
            Log.ERROR(f"XML Parse Error at line {error_line}, column {error_col}")
            Log.ERROR("Context:")
            for i in range(start_line, end_line):
                line_num = i + 1
                prefix = ">>> " if line_num == error_line else "    "
                Log.ERROR(f"{prefix}Line {line_num}: {lines[i][:200]}")  # Limit to 200 chars
            
            # Show the specific character at the error column
            if error_col <= len(problem_line):
                char_at_error = problem_line[error_col - 1] if error_col > 0 else ""
                Log.ERROR(f"Character at error position: '{char_at_error}' (ord={ord(char_at_error) if char_at_error else 'N/A'})")
                
                # Show a snippet around the error column
                start_col = max(0, error_col - 50)
                end_col = min(len(problem_line), error_col + 50)
                snippet = problem_line[start_col:end_col]
                pointer_pos = error_col - start_col - 1
                Log.ERROR(f"Snippet: {snippet}")
                Log.ERROR(f"         {' ' * pointer_pos}^")
    
    def _sanitize_xml(self, xml_content):
        """
        Attempt to fix common XML issues that cause parsing failures.
        """
        import html

        config = self.sanitizer_config

        def config_flag(name, default):
            value = config.get(name, default)
            return value if isinstance(value, bool) else default

        def configured_codepoints(name):
            values = config.get(name, [])
            if not isinstance(values, list):
                return set()

            codepoints = set()
            for value in values:
                if isinstance(value, int) and 0 <= value <= 0x10FFFF:
                    codepoints.add(value)
            return codepoints

        def configured_ranges(name):
            values = config.get(name, [])
            if not isinstance(values, list):
                return []

            ranges = []
            for value in values:
                if (
                    isinstance(value, list)
                    and len(value) == 2
                    and isinstance(value[0], int)
                    and isinstance(value[1], int)
                ):
                    start = max(0, min(value[0], value[1]))
                    end = min(0x10FFFF, max(value[0], value[1]))
                    ranges.append((start, end))
            return ranges

        def should_remove_codepoint(codepoint, removal_set, removal_ranges):
            if codepoint in removal_set:
                return True

            for start, end in removal_ranges:
                if start <= codepoint <= end:
                    return True

            return False
        
        # Fix common issues
        sanitized = xml_content
        
        # 1. Fix encoding issues FIRST - handle corrupted/invalid UTF-8 sequences
        # This handles the "EM" error characters you're seeing
        if config_flag('enable_encoding_cleanup', True):
            try:
                # Try to encode as UTF-8, replacing errors
                sanitized = sanitized.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
                if config_flag('drop_replacement_character', True):
                    # Remove the replacement character (�) that was inserted
                    sanitized = sanitized.replace('\ufffd', '')
            except:
                pass

        # Optional configurable direct replacements (after encoding cleanup, before XML filtering)
        replacements = config.get('replacements', {})
        if isinstance(replacements, dict):
            for old_value, new_value in replacements.items():
                if isinstance(old_value, str) and isinstance(new_value, str) and old_value:
                    sanitized = sanitized.replace(old_value, new_value)

        additional_remove_set = configured_codepoints('remove_codepoints')
        additional_remove_ranges = configured_ranges('remove_codepoint_ranges')
        
        # 2. Remove invalid XML characters (including those corrupted Japanese/special chars)
        # XML 1.0 valid characters: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
        # Remove everything else
        def is_valid_xml_char(char):
            codepoint = ord(char)
            return (
                codepoint == 0x09 or  # tab
                codepoint == 0x0A or  # newline
                codepoint == 0x0D or  # carriage return
                (0x20 <= codepoint <= 0xD7FF) or
                (0xE000 <= codepoint <= 0xFFFD) or
                (0x10000 <= codepoint <= 0x10FFFF)
            )
        
        # Filter out invalid characters
        sanitized = ''.join(
            char if (
                is_valid_xml_char(char)
                and not should_remove_codepoint(ord(char), additional_remove_set, additional_remove_ranges)
            ) else ''
            for char in sanitized
        )
        
        # 3. Fix unescaped ampersands (but not already escaped ones)
        if config_flag('escape_unescaped_ampersand', True):
            sanitized = re.sub(r'&(?!(?:amp|lt|gt|quot|apos);)', '&amp;', sanitized)
        
        # 4. Fix unescaped < and > in attribute values
        def fix_attribute_values(match):
            attr_value = match.group(1)
            # Escape < and > in attribute values
            attr_value = attr_value.replace('<', '&lt;').replace('>', '&gt;')
            return f'="{attr_value}"'
        
        if config_flag('escape_angle_brackets_in_attributes', True):
            sanitized = re.sub(r'="([^"]*[<>][^"]*)"', fix_attribute_values, sanitized)
        
        # 5. Normalize excessive whitespace in attribute values (but preserve single spaces)
        # This handles cases like UserText with many tabs/spaces or corrupted chars
        def normalize_whitespace(match):
            attr_name = match.group(1)
            attr_value = match.group(2)
            # Replace multiple whitespace chars with single space, then strip
            normalized = re.sub(r'\s+', ' ', attr_value).strip()
            return f'{attr_name}="{normalized}"'
        
        if config_flag('normalize_attribute_whitespace', True):
            sanitized = re.sub(r'(\w+)="([^"]*)"', normalize_whitespace, sanitized)
        
        # 6. Remove any remaining null bytes
        if config_flag('remove_null_bytes', True):
            sanitized = sanitized.replace('\x00', '')
        
        # 7. Final UTF-8 validation
        if config_flag('final_utf8_validation', True):
            try:
                # Ensure the result is valid UTF-8
                sanitized = sanitized.encode('utf-8', errors='ignore').decode('utf-8')
            except:
                pass
        
        Log.INFO("XML sanitization completed (removed invalid characters and fixed encoding)")
        return sanitized
    
    def _create_minimal_tree_from_regex(self, xml_content):
        """
        Create a minimal XML tree by extracting key attributes using regex.
        This is a fallback when XML parsing completely fails.
        """
        try:
            # Extract Lot attributes using regex
            lot_match = re.search(r'<Lot\s+([^>]+)>', xml_content, re.DOTALL)
            
            if not lot_match:
                Log.ERROR("Could not find Lot element in malformed XML")
                return None
            
            lot_attrs_str = lot_match.group(1)
            
            # Parse attributes from the Lot tag
            attr_pattern = r'(\w+)="([^"]*)"'
            attributes = dict(re.findall(attr_pattern, lot_attrs_str))
            
            # Create a minimal XML structure
            root = ET.Element('STDML')
            lot_elem = ET.SubElement(root, 'Lot', attrib=attributes)
            
            Log.INFO(f"Created minimal tree with {len(attributes)} Lot attributes")
            Log.INFO(f"Extracted attributes: {list(attributes.keys())}")
            
            return root
            
        except Exception as e:
            Log.ERROR(f"Failed to create minimal tree from regex: {e}")
            return None

        self.filename = None
        self.tester_type = None
        self.waferids = None
               
        
    def get_recipe(self):
        recipe_elem = self.root.find(".//Attribute[@Name='Recipe']")
        if recipe_elem is not None:
            return recipe_elem.get("Value")
        else:
            return None
        
    def get_product(self):
        product_elem = self.root.find(".//Attribute[@Name='Product']")
        if product_elem is not None:
            return product_elem.get("Value")
        else:
            return None
    
    def get_lotid(self):
        lotid_elem = self.root.find(".//Attribute[@Name='LotId']")
        if lotid_elem is not None:
            return lotid_elem.get("Value")
        else:
            return None

    def get_upm_lotid(self):
        if self.xml_content is not None:
            lot_id_match = re.search(r'LotId="([^"]+)"', self.xml_content)
            if lot_id_match:
                return lot_id_match.group(1)
            else:
                Log.INFO("LotId attribute not found")
        else:
            Log.INFO("XML content is None")
        return None

    def get_upm_wafernr(self):
        if self.xml_content is not None:
            wafer_nr_match = re.search(r'WaferNr="([^"]+)"', self.xml_content)
            if wafer_nr_match:
                return wafer_nr_match.group(1)
            else:
                Log.INFO("WaferNr attribute not found")
        else:
            Log.INFO("XML content is None")
        return None
  
    def get_lot_attributes_as_dict_from_stdml_format(self):
        """
        Convert the attributes of the <Lot> element to a dictionary.
        
        Returns:
        dict: A dictionary representation of the <Lot> element's attributes.
        """
        model = Model()
        wafer = Wafer()
        
        lot_element = self.root.find('Lot')
        if lot_element is not None:
            # model = Model()
            # wafer = Wafer()
            attributes = {}
            for attr in lot_element.attrib:
                if attr == "WAFER_NO":
                    wafer.number = lot_element.attrib[attr]
                    model.add("wafers", wafer)
                attributes[attr] = lot_element.attrib[attr]
            return attributes, model
        else:
            Log.error("No <Lot> element found in the XML data.")
            Util.dp_exit(1, pplogger=self.pplogger, error=f"No <Lot> element found in the XML data.")
            # return {}

    def add_metadata_to_xml(self, metadata_dto):
        # Parse the existing XML
        # root = ET.fromstring(xml_string)

        # Create the Metadata element
        metadata_element = ET.Element("Metadata")

        # Add attributes from the MetadataDTO to the Metadata element
        for key, attribute in metadata_dto.get_metadata_dto_attributes().items():
            attribute_element = ET.SubElement(metadata_element, "Attribute")
            attribute_element.set("Value", attribute.value)
            attribute_element.set("Source", attribute.source)
            attribute_element.set("Name", attribute.name)

        # Insert the Metadata element at the top of the existing XML
        self.root.insert(0, metadata_element)

        # Convert back to string
        return ET.tostring(self.root, encoding='unicode')
   
    def get_lot_attributes_and_units(self):
        """
        Convert the attributes of the <Lot> element to a dictionary and process units.
        
        Returns:
        dict: A dictionary representation of the <Lot> element's attributes.
        Model: The model containing wafers and dies.
        """
        model = Model()
        wafer = Wafer()
        
        lot_element = self.root.find('.//Lot')
        if lot_element is not None:
            attributes = {}
            counter = 1
            for attr in lot_element.attrib:
                if attr == "WAFER_NO":
                    wafer_number = lot_element.attrib[attr]
                    # Log.INFO(f"WaferNumber={wafer_number}")
                    wafer.number = wafer_number
                    model.add("wafers", wafer)
                    # print(f"TEST={counter}")
                    counter += 1
                elif attr == "SublotId":  # Check for SubLotId attribute
                    sublot_id = lot_element.attrib[attr]
                    # Log.INFO(f"SubLotId={sublot_id}")
                    wafer.number = sublot_id
                    model.add("wafers", wafer)
                    # print(f"TEST={counter}")
                    counter += 1

                attributes[attr] = lot_element.attrib[attr]
            
            # Ensure there is at least one wafer in the wafers list
            if not model.wafers:
                Log.error("No wafers found in the model.")
                Util.dp_exit(1, pplogger=self.pplogger, error="No wafers found in the model")

            # Access the first wafer
            wafer = model.wafers[0]
            
            parametric_data = lot_element.find('ParametricData')
            if parametric_data is not None:
                # print(f"TEST=2")
                for unit in parametric_data.findall('Unit'):
                    die = Die()
                    die.x = int(unit.get('X'))
                    die.y = int(unit.get('Y'))
                    die.hard_bin = int(unit.get('HardBin'))
                    die.soft_bin = int(unit.get('SoftBin'))
                    # print("+++++++++++++++++++++++++++++++++++++")
                    
                    results = {}
                    for meas in unit.findall('Meas'):
                        pmid = int(meas.get('PmId'))
                        pf = int(meas.get('PF')) if meas.get('PF') is not None else None  # Check for PF
                        val = float(meas.get('Val')) if meas.get('Val') is not None else None  # Check for Val
                        results[pmid] = {'value': val, 'pass_fail': pf}
                    
                    die.results = results
                    wafer.add('dies', die)
            
            return attributes, model
        else:
            Log.error("No <Lot> element found in the XML data.")
            Util.dp_exit(1, pplogger=self.pplogger, error="No <Lot> element found in the XML data.")
