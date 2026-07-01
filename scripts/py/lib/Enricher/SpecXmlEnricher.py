import gzip
import re
from lib.Util import Util
from lib.Utility.JndUtil import JndUtil
from lib.Log import Log


class SpecXmlEnricher:
    def __init__(self, input_txt, refdb_api_client, ws_urls, default_onscribe_metadata, default_onlot_metadata):
        self._txt_raw_file = input_txt  # Changed variable name for text file
        self.refdb_api_client = refdb_api_client
        self.ws_urls = ws_urls
        # self.waferids_json = waferids_json
        self.waferids = {}
        self.default_onscribe_metadata = default_onscribe_metadata
        self.default_onlot_metadata = default_onlot_metadata
        self.new_waferids = {}
        self._txt_enriched = []  # Changed to store enriched text lines
        self._txt_content = ""
        
        # Check if the file is compressed
        if input_txt.endswith('.gz'):
            # Data is compressed, decompress it
            with gzip.open(input_txt, 'rb') as f:
                self._txt_content = f.read().decode('utf-8', errors='replace')  # Decode with error handling
        else:
            # Read the text file directly
            with open(input_txt, 'rb') as f:  # Open in binary mode
                self._txt_content = f.read().decode('utf-8', errors='replace')  # Decode with error handling

    def enrich(self, lot, jnd_mother_lot, jnd_sourceLot, lot_metadta_file, waferids):
        # Clear the enriched list at the start of the function
        self._txt_enriched = []  # Initialize the list to store enriched lines
       
        # Load lot and scribe data
        lot_metadata, last_lot_metadata = JndUtil.load_jnd_lot_metadata(lot_metadta_file)
        # print(f"LOTM={lot_metadata}")
        jnd_mother_lot = jnd_mother_lot
        jnd_sourceLot = jnd_sourceLot

        # Process the text content instead of XML
        for line in self._txt_content.splitlines():  # Split content into lines
            modified_line = line  # Create a copy of the line for modification
            stripped_line = line.strip()  # Strip leading and trailing whitespace

          
            if stripped_line.startswith("<Lot "):  # Check if the line starts with <Lot
                if lot in lot_metadata:
                    # Extract existing attributes
                    attributes = {}
                    for attr_match in re.finditer(r'(\w+)="([^"]*)"', stripped_line):
                        key, value = attr_match.groups()
                        attributes[key] = value

                    # Update/add required attributes
                    attributes['LotId'] = lot
                    attributes['ParentLot'] = lot_metadata[lot].get('ParentLot', '') or re.sub(r'\.\d+$', '.1', lot)
                    attributes['Device'] = lot_metadata[lot].get('TPNO', '').strip()  # Set Device from TPNO
                    
                    # Add other metadata attributes
                    for key in ['TPNO', 'AccountCode', 'MBNO', 'Process', 'Technology', 'Fab', 'SourceLot', 'LotType']:
                        attributes[key] = lot_metadata[lot].get(key, '')

                    # Reconstruct the line with all attributes
                    attr_str = ' '.join(f'{k}="{v}"' for k, v in attributes.items())
                    modified_line = f'<Lot {attr_str}>'
                else:
                    # Similar process for last_lot_metadata
                    attributes = {}
                    for attr_match in re.finditer(r'(\w+)="([^"]*)"', stripped_line):
                        key, value = attr_match.groups()
                        attributes[key] = value

                    attributes['ParentLot'] = last_lot_metadata.get('ParentLot', '') or re.sub(r'\.\d+$', '.1', lot)
                    attributes['Device'] = last_lot_metadata.get('TPNO', '').strip()  # Set Device from TPNO

                    for key in ['TPNO', 'AccountCode', 'MBNO', 'Process', 'Technology', 'Fab', 'SourceLot', 'LotType']:
                        attributes[key] = last_lot_metadata.get(key, '')

                    attr_str = ' '.join(f'{k}="{v}"' for k, v in attributes.items())
                    modified_line = f'<Lot {attr_str}>'
               

            # Process wafer information
            if stripped_line.startswith("<SubLot "):  # Check if the line starts with <Wafer
                # print(f"Processing Wafer line: {line}")
                vid_match = re.search(r'Vid="([^"]*)"', line)
                if vid_match:
                    vid = vid_match.group(1)
                    # vid = vid.zfill(2)
                    vid = Util.format_wafer_number(vid)
                    lot_wafer_key = f"{lot}_{vid}"
                    onlot_metadata = self.default_onlot_metadata
                    onscribe_metadata = self.default_onscribe_metadata
                    onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'lot', lot)
                    onscribe_metadata = Util.replace_dict_value(onscribe_metadata, 'waferNum', vid)
                    onlot_metadata =  Util.replace_dict_value(onlot_metadata, 'lot', lot)
                    onlot_metadata = Util.replace_dict_value(onlot_metadata, "sourceLot", jnd_sourceLot)
                    onscribe_metadata = Util.update_wafer_id(onscribe_metadata, jnd_sourceLot, vid)
                    waferid = onscribe_metadata.get('waferId', 'NA')
                    if Util.looks_like_number(vid):
                        waferid = JndUtil.get_waferid_scribe_file(lot, vid, waferids)
                        if waferid == 'NA':
                            onscribe_metadata, new_lot_wafer_key = JndUtil.get_jnd_onscribe_metadata(self.refdb_api_client, self.ws_urls, jnd_sourceLot, waferids, lot, vid, onscribe_metadata, onlot_metadata)
                            waferid = onscribe_metadata.get('waferId', 'NA')
                            if isinstance(onscribe_metadata, dict) and onscribe_metadata['status'].upper() == 'MANUAL':
                                Log.INFO(f"WAFERID from ERT={waferid} will be used.")
                                for key in [new_lot_wafer_key, lot_wafer_key]:
                                    if key not in self.new_waferids:
                                        self.new_waferids[key] = waferid
                            else:
                                Log.INFO(f"CALCULATED WAFERID={waferid} will be used.")
                        else:
                            Log.INFO(f"WAFERID from Scribe/ShipScribe reference file={waferid} will be used.")
                    else:
                        Log.INFO(f"No valid wafer number={slot}, WAFERID{waferid} will be NA.")
                                      
                    # Update the line with LaserScribe
                    modified_line = re.sub(r'>$', f' LaserScribe="{waferid}">', modified_line)  # Add LaserScribe field
                    # print(f"Added LaserScribe to line: {modified_line}")

            self._txt_enriched.append(modified_line)  # Append enriched line
        return self._txt_enriched, self.new_waferids  # Return the list of enriched lines




