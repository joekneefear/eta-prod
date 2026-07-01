"""
SYNOPSIS

DESCRIPTION

Sxml Enricher class

AUTHOR

junifferallan.garcia@onsemi.com

CHANGES
2023-Sep-06 - jgarcia - initial
2023-Sep-15 - jgarcia - refactor enrich_sxml_with_wmc method to not use xml libraries, instead parse and update as a file,
                        this is to eliminate the issue of custom closing tags are being replaced with /> or being auto closed.
                        we want to preserve the original sxml format for format reader.
2024-Sep-17 - jgarcia - added enrichement support for JND Probe Advantest xml 
2024-Sep-17 - jgarcia - refactored to wmc enrichment
2025-Dec-15 - jgarcia - added enrich_bin_element_no_update function to be used by Tesec sxml bin enrichment instead of enrich_bin_element
                        to fix bug on SBM incorrect PASS bin settings loaded to Exensio
2026-Mar-18 - jgarcia - added error handling to enrich_sxml_with_wmc_and_return_as_list method to log the error and return the original content with metadata only as a fallback instead of exiting the program, this is to prevent the entire enrichment process from failing due to an error in wmc enrichment, and to allow the rest of the metadata enrichment to still be applied and returned.


LICENSE

(C) onsemi 2023 All rights reserved.
"""

import sys
import re
import gzip
from lib.Util import Util
from lib.Log import Log
import xml.etree.ElementTree as ET
import traceback

class SxmlEnricher:
    
    def __init__(self, input_xml):
        self._xml_raw_file = input_xml
        self._xml_enriched = []
        self._xml_content = ""
        self._xml_lines_in_list = []
        
    def add_custom_attribute(self, name, value, source):
        metadata_start = None
        metadata_end = None
        for i, line in enumerate(self.xml_lines):
            if '<Metadata>' in line:
                metadata_start = i
            elif '</Metadata>' in line:
                metadata_end = i
        
        if metadata_start is not None and metadata_end is not None:
            custom_attr_line = f'<Attribute Name="{name}" Value="{value}" Source="{source}"></Attribute>'
            self.xml_lines.insert(metadata_end, custom_attr_line)
            
    def enrich_sxml_with_wmc_and_return_as_list(self, wmc_dict, source_dict):
        try:
            for attribute_name, attribute_value in wmc_dict.items():
                updated = False
                for i, line in enumerate(self._xml_enriched):
                    if f'Name="{attribute_name}"' in line:
                        # Update the existing attribute's Value and Source
                        source_value = source_dict.get(attribute_name, 'FJM')  # Get Source value from source_dict
                        updated_line = re.sub(r'Value="[^"]+"', f'Value="{attribute_value}"', line)
                        updated_line = re.sub(r'Source="[^"]+"', f'Source="{source_value}"', updated_line)
                        self._xml_enriched[i] = updated_line
                        updated = True
                        break

                if not updated:
                    # If the element does not exist, find the index of </Metadata>
                    metadata_end = None
                    for i, line in enumerate(self._xml_enriched):
                        if '</Metadata>' in line:
                            metadata_end = i
                            break
                    if metadata_end is not None:
                        # Create a new custom attribute line
                        source_value = source_dict.get(attribute_name, 'FJM')  # Get Source value from source_dict
                        custom_attr_line = f'<Attribute Name="{attribute_name}" Value="{attribute_value}" Source="{source_value}"></Attribute>'
                        self._xml_enriched.insert(metadata_end, custom_attr_line)

            return self._xml_enriched
        except Exception as e:
            Log.ERROR(f"An error occurred:{e}")
            Util.dp_exit(1, f"An Exception occured:{e}")
            raise
        
    def enrich_clean_test_name_and_test_desc(self):
        try:
            if self._xml_raw_file.endswith('.gz'):
                # Data is compressed, decompress it
                with gzip.open(self._xml_raw_file, 'rb') as gz_file:
                    xml_content = gz_file.read().decode('utf-8')
            else:
                # Data is not compressed
                with open(self._xml_raw_file, 'r', encoding='utf-8') as xml_file:
                    xml_content = xml_file.read()
            self._xml_content = xml_content.split('\n')
            
            self._xml_enriched = []  # Create a list to store updated content
            
            for line in self._xml_content:
                # Use regular expressions to capture TestName and TestDescription attributes
                updated_xml_content = re.sub(r'<Param\s+(.*?)>', lambda x: self.clean_param_attributes(x.group(0)), line)
                
                # Use regular expression to capture the Name attribute in the Bin section
                updated_xml_content = re.sub(r'<Bin\s+(.*?)>', lambda x: self.clean_bin_attributes(x.group(0)), updated_xml_content)
                
                self._xml_enriched.append(updated_xml_content)  # Append the updated content to the list
        except Exception as e:
            Log.ERROR(f"An error occurred: {e}")
            Util.dp_exit(1, f"An Exception occured->enrich_clean_test_name_and_test_desc<- method:{e}")
            raise
    
    def clean_param_attributes(self, param_match):
        # Extract the TestName and TestDescription attributes
        match = re.search(r'TestName="([^"]*)"', param_match)
        test_name = match.group(1) if match else ''
        
        match = re.search(r'TestDescription="([^"]*)"', param_match)
        test_description = match.group(1) if match else ''
        
        # Clean TestName and TestDescription attributes
        clean_test_name = Util.clean_spaces(test_name)
        clean_test_description = Util.clean_spaces(test_description)
        
        # Replace the original attributes with the cleaned attributes
        return re.sub(
            r'TestName="([^"]*)"',
            f'TestName="{clean_test_name}"',
            re.sub(r'TestDescription="([^"]*)"', f'TestDescription="{clean_test_description}"', param_match)
        )

    def clean_bin_attributes(self, bin_match):
        # Extract the Name attribute in the Bin section
        match = re.search(r'Name="([^"]*)"', bin_match)
        bin_name = match.group(1) if match else ''
        
        # Clean the Name attribute
        clean_bin_name = bin_name.strip()
        
        # Replace the original attribute with the cleaned attribute
        return re.sub(r'Name="([^"]*)"', f'Name="{clean_bin_name}"', bin_match)
    
    def enrich_xml(self, metadata, testnames=None):
        try:
            # Read and process the input file
            if self._xml_raw_file.endswith('.gz'):
                # Data is compressed, decompress it
                with gzip.open(self._xml_raw_file, 'rb') as gz_file:
                    xml_content = gz_file.read().decode('utf-8')
            else:
                # Data is not compressed
                with open(self._xml_raw_file, 'r', encoding='utf-8') as xml_file:
                    xml_content = xml_file.read()
            
            self._xml_lines_in_list = xml_content.split('\n')
            self._xml_enriched = []  # Create a list to store updated content

            metadata_inserted = False
            root_tag_found = False
            part_index = 1  # Initialize PartIndex

            for line in self._xml_lines_in_list:
                if not root_tag_found and line.strip().startswith('<'):
                    root_tag_found = True
                    self._xml_enriched.append(line)
                    if not metadata_inserted:
                        self._xml_enriched.extend(metadata.splitlines())
                        metadata_inserted = True
                else:
                    updated_line = line

                    try:
                        # File element enrichment
                        if '<File ' in updated_line:
                            updated_line = self.enrich_file_element(updated_line)

                        # Param element enrichment
                        if '<Param ' in updated_line:
                            updated_line = self.enrich_param_element(updated_line, testnames) #if testnames else updated_line

                        # Bin element enrichment
                        if '<Bin ' in updated_line:
                            # updated_line = self.enrich_bin_element(updated_line) #replaced by enrich_bin_element_no_update
                            updated_line = self.enrich_bin_element_no_update(updated_line)

                        # Add PartIndex to Unit elements
                        updated_line = self.add_part_index_to_unit(updated_line, part_index)
                        if '<Unit ' in updated_line:
                            part_index += 1
                    except Exception as line_error:
                        Log.WARN(f"Error enriching line (continuing anyway): {line_error}")
                        # Continue with the original line if enrichment fails
                        pass

                    self._xml_enriched.append(updated_line)

            return self._xml_enriched

        except Exception as e:
            Log.ERROR(f"An error occurred while enriching XML: {e}")
            Log.WARN("Attempting to return original content with metadata only...")
            
            # Fallback: return original content with metadata inserted
            try:
                if self._xml_lines_in_list:
                    fallback_content = []
                    root_tag_found = False
                    for line in self._xml_lines_in_list:
                        if not root_tag_found and line.strip().startswith('<'):
                            root_tag_found = True
                            fallback_content.append(line)
                            fallback_content.extend(metadata.splitlines())
                        else:
                            fallback_content.append(line)
                    return fallback_content
            except:
                pass
            
            Util.dp_exit(1, f"An Exception occurred in enrich_xml method: {e}")
            raise

    def enrich_file_element(self, line):
        file_name_match = re.search(r'FileName="([^"]*)"', line)
        if file_name_match:
            file_name = file_name_match.group(1)
            file_datetime = re.search(r'\d{14}', file_name)
            if file_datetime:
                formatted_datetime = f"{file_datetime.group()[:4]}/{file_datetime.group()[4:6]}/{file_datetime.group()[6:8]} {file_datetime.group()[8:10]}:{file_datetime.group()[10:12]}:{file_datetime.group()[12:14]}"
                line = re.sub(r'(FileName="[^"]*")', f'\\1 FileDateTime="{formatted_datetime}"', line)
        return line

    def enrich_param_element(self, line, testnames):
        testnumber = ""
        
        # Match ITEM_NAME="..."
        item_name_match = re.search(r' ITEM_NAME="([^"]*)"', line)
        if item_name_match:
            item_name = item_name_match.group(1)
            
            # Match digits in ITEM_NAME
            testnumber_match = re.search(r'[0-9]+', item_name)
            if testnumber_match:
                testnumber = int(testnumber_match.group(0))
            
            testname = testnames.get(item_name, "")
            # Log.INFO(f"Item Name: {item_name}, Test Name: {testname}")  # Debugging line
            
            # Enrich the line
            if testnumber:
                line = re.sub(r'><\/Param>$', f' TestNumber="{testnumber}"></Param>', line)
            if testname:
                line = re.sub(r'><\/Param>$', f' TestName="{testname}"></Param>', line)
                
        # clean testname and test descrtipion
        match = re.search(r'TestName="([^"]*)"', line)
        test_name = match.group(1) if match else ''
        
        match = re.search(r'TestDescription="([^"]*)"', line)
        test_description = match.group(1) if match else ''
        
        # Clean TestName and TestDescription attributes
        clean_test_name = Util.clean_spaces(test_name)
        clean_test_description = Util.clean_spaces(test_description)
        
        line = re.sub(r'TestName="([^"]*)"', f'TestName="{clean_test_name}"', re.sub(r'TestDescription="([^"]*)"', f'TestDescription="{clean_test_description}"', line))
        
        # Remove TEST_NAME
        line = re.sub(r' TEST_NAME="[^"]*"', '', line)
        
        # Replace UNIT with Units
        line = re.sub(r' UNIT="([^"]*)"', r' Units="\1"', line)
        
        # Replace SPEC_MIN with LowLimit
        line = re.sub(r' SPEC_MIN="([^"]*)"', r' LowLimit="\1"', line)
        
        # Replace SPEC_MAX with HighLimit
        line = re.sub(r' SPEC_MAX="([^"]*)"', r' HighLimit="\1"', line)
        
        # Replace Scale with ResultScale
        line = re.sub(r' Scale="([^"]*)"', r' ResultScale="\1"', line)
        
        return line

    def enrich_bin_element(self, line):
        # Check if Site and Head attributes already exist
        if 'Site="' not in line and 'Head="' not in line:
            # Add Site and Head attributes at the beginning of the <Bin> element
            line = re.sub(r'(<Bin\s+)', r'\1Site="255" Head="255" ', line)

        # Replace CATEGORY with Number
        line = re.sub(r'CATEGORY="(\d+)"', r'Number="\1"', line)
        
        # Extract the Number and Type attributes
        number_match = re.search(r'Number="(\d+)"', line)
        type_match = re.search(r'Type="(Hardware|Software)"', line)
        
        if number_match and type_match:
            number = int(number_match.group(1))
            bin_type = type_match.group(1)
            
            # Determine the Name value based on the Type
            if bin_type == 'Hardware':
                name_value = f'HWBin_{number}'
            elif bin_type == 'Software':
                name_value = f'SWBin_{number}'
            
            # Add the Name attribute if it doesn't exist
            if 'Name="' not in line:
                line = re.sub(r'(Type="[^"]*")', f'\\1 Name="{name_value}"', line)
            
            # Determine the PassFail value based on the Type and Number
            if bin_type == 'Hardware':
                pass_fail = 'P' if number == 1 else 'F'
            elif bin_type == 'Software':
                pass_fail = 'P' if number == 9999 else 'F'
            
            # Add the PassFail attribute
            line = re.sub(r'(Type="[^"]*")', f'\\1 PassFail="{pass_fail}"', line)
        
        return line
    
    def enrich_bin_element_no_update(self, line: str) -> str:
        """
        Enrich a single HTML-escaped <Bin> element line without updating or duplicating
        any attribute that is already present.

        Behavior:
        - Adds Site="255" only if missing.
        - Adds Head="255" only if missing.
        - Never converts CATEGORY -> Number.
        - Requires Type="Hardware" or Type="Software" + Number="<int>" to derive Name/PassFail.
        - Adds Name as "HWBin_<Number>" or "SWBin_<Number>" only if missing.
        - Adds PassFail only if missing, using: pass_fail = 'P' if number == 1 else 'F'.
        - Never changes existing values; never duplicates attributes.
        """
        # Only process lines that start with the Bin tag (HTML-escaped)
        if not re.match(r'^\s*&lt;Bin\b', line):
            return line

        def insert_after_tag(attr_text: str, s: str) -> str:
            # Insert right after '&lt;Bin' with a single space; preserve any existing spacing
            return re.sub(r'(&lt;Bin\b)(\s*)', r"\1 " + attr_text + r" ", s, count=1)

        # Ensure Site
        if 'Site="' not in line:
            line = insert_after_tag('Site="255"', line)

        # Ensure Head
        if 'Head="' not in line:
            line = insert_after_tag('Head="255"', line)

        # Extract Number and Type (no CATEGORY conversion)
        number_match = re.search(r'Number="(\d+)"', line)
        type_match   = re.search(r'Type="(Hardware|Software)"', line)

        if number_match and type_match:
            number   = int(number_match.group(1))
            bin_type = type_match.group(1)

            # Add Name only if missing (prefix depends on Type)
            if 'Name="' not in line:
                name_value = f'{"HWBin" if bin_type == "Hardware" else "SWBin"}_{number}'
                line = re.sub(r'(Type="[^"]*")', f'\\1 Name="{name_value}"', line, count=1)

            # Add PassFail only if missing (simplified rule)
            if 'PassFail="' not in line:
                pass_fail = 'P' if number == 1 else 'F'
                line = re.sub(r'(Type="[^"]*")', f'\\1 PassFail="{pass_fail}"', line, count=1)

        return line


    def add_part_index_to_unit(self, line, part_index):
        """Add PartIndex attribute to Unit elements."""
        if '<Unit ' in line:
            return re.sub(r'(<Unit [^>]*)(>)', f'\\1 PartIndex="{part_index}"\\2', line)
        return line
    
    def enrich_upm(self, lot, waferid, lot_metadata, last_lot_metadata):
        try:
            # Read and process the input file
            if self._xml_raw_file.endswith('.gz'):
                # Data is compressed, decompress it
                with gzip.open(self._xml_raw_file, 'rb') as gz_file:
                    xml_content = gz_file.read().decode('utf-8')
            else:
                # Data is not compressed
                with open(self._xml_raw_file, 'r', encoding='utf-8') as xml_file:
                    xml_content = xml_file.read()
            
            self._xml_lines_in_list = xml_content.split('\n')
            
            # Ensure we are working with the specific lot's metadata
            if lot in lot_metadata:
                lot_metadata[lot].pop('MBNO', None)
                current_metadata = lot_metadata[lot]
            else:
                current_metadata = last_lot_metadata.copy()
                current_metadata.pop('MBNO', None)
            
            for i, line in enumerate(self._xml_lines_in_list):
                temp_line = line.lstrip()
                
                if temp_line.startswith("<Lot"):
                    if re.search(r' Mask=\"[^\"]*\"', line):
                        # Construct metadata_str from the specific lot's metadata
                        metadata_str = ' '.join([f'{key}="{value}"' for key, value in current_metadata.items()])
                        updated_line = re.sub(r'( Mask=\"[^\"]*\")', r'\1 ' + metadata_str, line)
                        self._xml_lines_in_list[i] = updated_line
                        
                elif temp_line.startswith("<WaferData"):
          
                    if re.search(r'">$', line):
                        updated_line = re.sub(r'">$', f'" LaserScribe="{waferid}">', line)
                        self._xml_lines_in_list[i] = updated_line
            
            return self._xml_lines_in_list
        
        except Exception as e:
            Log.ERROR(f"An error occurred: {e}")
            Log.ERROR(traceback.format_exc())
            Util.dp_exit(1, 'An error occurred during UPM XML enrichment')

            

        
