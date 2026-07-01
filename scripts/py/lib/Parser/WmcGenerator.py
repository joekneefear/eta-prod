"""
SYNOPSIS

DESCRIPTION
    This script will parse needed info from FrJM and calculate wafermap configuration for Exensio.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Sep-14 - jgarcia - initial
    2024-Jul-24 - jgarcia - do not error out if device is not in the wmc ref file. wmc ref file is now not a requirement.

LICENSE
    (C) onsemi 2023 All rights reserved.
"""

import re
from lib.Log import Log
from lib.Util import Util

class WmcGenerator:
    def __init__(self, input_file, ref_file):
        self.input_file = input_file
        self.wmc_coordinates_ref_file = ref_file
        # self.logger = Log.logger
        self.reset_values()
        self.parse()
        self.get_wmc_reference()
        self.perform_computations_and_initialize_wmc_attribute()
    
    def reset_values(self):
        self.header = False
        self.lay_in = False
        self.wafermap = False
        self.chip = False
        self.isFOUND = True
        self.extracted_values = {}
        self.coord_references = {}
        self.wmc_attribute = {}
        self.calculated_values = {}

    def parse(self):
        X_FRSTACT = 0
        Y_FRSTACT = 0
        X_MINACT = 0
        X_MAXACT = 0
        Y_MINACT = 0
        Y_MAXACT = 0
        CENT_DISTX = 0
        CENT_DISTY = 0
        # Define regular expressions for matching patterns
        layoutno_pattern = re.compile(r'^LAYOUTNO=\s?(.+)')
        tpno_pattern = re.compile(r'^TPNO=\s?(.+)')
        mbno_pattern = re.compile(r'^MBNO=\s?(.+)')
        mask_pattern = re.compile(r'^MASK=\s?(.+)')
        w_size_pattern = re.compile(r'^W_SIZE=\s?(.+)')
        chip_x_pattern = re.compile(r'^CHIP_X=\s?(.+)')
        chip_y_pattern = re.compile(r'^CHIP_Y=\s?(.+)')
        block_x_pattern = re.compile(r'^BLOCK_X=\s?(.+)')
        block_y_pattern = re.compile(r'^BLOCK_Y=\s?(.+)')
        cx_addr_pattern = re.compile(r'^CX_ADDR=\s?(.+)')
        cy_addr_pattern = re.compile(r'^CY_ADDR=\s?(.+)')
        c_code_pattern = re.compile(r'^C_CODE=\s?(.+)')
        cdist_x_pattern = re.compile(r'^CDIST_X=\s?(.+)')
        cdist_y_pattern = re.compile(r'^CDIST_Y=\s?(.+)')
        data_pattern = re.compile(r'^DATA=[0-9][0-9][0-9][0-9][0-9][0-9]')
        with open(self.input_file, 'r', encoding='ISO-8859-1') as file:
            
            for line in file:
                line = line.strip()
                # self.process_line(line)
                # Check for header section
                if line == "[HEADER]":
                    self.header = True
                    continue
                if self.header:
                    # Check for header fields
                    match = layoutno_pattern.match(line)
                    if match:
                        self.extracted_values['LAYOUTNO'] = match.group(1)
                        continue
                    match = tpno_pattern.match(line)
                    if match:
                        self.extracted_values['TPNO'] = match.group(1)
                        continue
                    match = mbno_pattern.match(line)
                    if match:
                        self.extracted_values['MBNO'] = match.group(1)
                        continue
                    match = mask_pattern.match(line)
                    if match:
                        self.extracted_values['MASK'] = match.group(1)
                        continue
                # Check for LAY_IN section
                if line == "[LAY_IN]":
                    self.lay_in = True
                    continue
                if self.lay_in:
                    # Check for LAY_IN fields
                    match = w_size_pattern.match(line)
                    if match:
                        self.extracted_values['W_SIZE'] = match.group(1)
                        continue
                    match = chip_x_pattern.match(line)
                    if match:
                        self.extracted_values['CHIP_X'] = match.group(1)
                        continue
                    match = chip_y_pattern.match(line)
                    if match:
                        self.extracted_values['CHIP_Y'] = match.group(1)
                        continue
                    match = block_x_pattern.match(line)
                    if match:
                        self.extracted_values['BLOCK_X'] = match.group(1)
                        continue
                    match = block_y_pattern.match(line)
                    if match:
                        self.extracted_values['BLOCK_Y'] = match.group(1)
                        continue
                
                # Check for WAFERMAP section
                if line == "[WAFERMAP]":
                    self.wafermap = True
                    continue
                if self.wafermap:
                    # Check for WAFERMAP fields
                    match = cx_addr_pattern.match(line)
                    if match:
                        self.extracted_values['CX_ADDR'] = match.group(1)
                        continue
                    match = cy_addr_pattern.match(line)
                    if match:
                        self.extracted_values['CY_ADDR'] = match.group(1)
                        continue
                    match = c_code_pattern.match(line)
                    if match:
                        self.extracted_values['C_CODE'] = match.group(1)
                        continue
                    match = cdist_x_pattern.match(line)
                    if match:
                        self.extracted_values['CDIST_X'] = match.group(1)
                        continue
                    match = cdist_y_pattern.match(line)
                    if match:
                        self.extracted_values['CDIST_Y'] = match.group(1)
                        continue
                
                # Check for CHIP section
                if line == "[CHIP]":
                    self.chip = True
                    continue
                if self.chip:
                    # Check for CHIP fields
                    
                    match = data_pattern.match(line)
                    if match:
                        data_of_interest = line.split('=')
                        data = data_of_interest[1].split(',')

                        if self.isFOUND:
                            if int(data[0]) > 0 and int(data[3]) >= 101:
                                X_FRSTACT = int(data[1])
                                Y_FRSTACT = int(data[2])
                                X_MINACT = int(data[1])
                                X_MAXACT = int(data[1])
                                Y_MINACT = int(data[2])
                                Y_MAXACT = int(data[2])
                                self.isFOUND = False
                                if int(data[3]) == int(self.extracted_values['C_CODE']):
                                    CENT_DISTX = float(data[9])
                                    CENT_DISTY = float(data[10])
                            if int(data[0]) >= 101:
                                if int(data[1]) < int(X_MINACT):
                                    X_MINACT = int(data[1])
                                if int(data[1]) > int(X_MAXACT):
                                    X_MAXACT = int(data[1])
                                if int(data[2]) < int(Y_MINACT):
                                     Y_MINACT = int(data[2])
                                if int(data[2]) > int(Y_MAXACT):
                                    Y_MAXACT = int(data[2])
                                    
                        if int(data[3]) == int(self.extracted_values['C_CODE']):
                            CENT_DISTX = float(data[9])
                            CENT_DISTY = float(data[10])
                            
                        if int(data[0]) >= 101:
                            if int(data[1]) < int(X_MINACT):
                                X_MINACT = int(data[1])
                            if int(data[1]) > int(X_MAXACT):
                                X_MAXACT = int(data[1])
                            if int(data[2]) < int(Y_MINACT):
                                Y_MINACT = int(data[2])
                            if int(data[2]) > int(Y_MAXACT):
                                Y_MAXACT = int(data[2])
                                
        # print(f"X_FRSTACT={X_FRSTACT}||Y_FRSTACT={Y_FRSTACT}||X_MINACT={X_MINACT}||X_MAXACT={X_MAXACT}||Y_MINACT={Y_MINACT}||Y_MAXACT={Y_MAXACT}||CENT_DISTX={CENT_DISTX}||CENT_DISTY={CENT_DISTY}")
        self.extracted_values['X_FRSTACT'] = X_FRSTACT
        self.extracted_values['Y_FRSTACT'] = Y_FRSTACT
        self.extracted_values['X_MINACT'] = X_MINACT
        self.extracted_values['X_MAXACT'] = X_MAXACT
        self.extracted_values['Y_MINACT'] = Y_MINACT
        self.extracted_values['Y_MAXACT'] = Y_MAXACT
        self.extracted_values['CENT_DISTX'] = CENT_DISTX
        self.extracted_values['CENT_DISTY'] = CENT_DISTY
        self.calculated_values['X_PROJCEN'] =  (int(X_MAXACT) + int(X_MINACT)) / 2
        self.calculated_values['Y_PROJCEN'] =  (int(Y_MAXACT) + int(Y_MINACT)) / 2
        # print(self.extracted_values)

                        
    def get_wmc_reference(self):
        # Read coordinates reference file
        with open(self.wmc_coordinates_ref_file, 'r') as coord_file:
            for line in coord_file:
                parts = line.strip().split(',')
                if len(parts) == 3:
                    device, x_frstref, y_frstref = parts
                    self.coord_references[device] = (int(x_frstref), int(y_frstref))
                else:
                    Log.INFO("wmc coordinates' info could be lacking in information")
                    # Util.dp_exit(1,f"check wmc coordinates ref file with device={device} if complete info")

        # Add new key-value pairs based on your logic...
        if 'TPNO' in self.extracted_values and self.extracted_values['TPNO'] is not None:
            tpno = self.extracted_values['TPNO']
            if len(tpno) >= 4:  # Check for a valid length
                device = tpno[-4:]
            if device in self.coord_references:
                x_frstref, y_frstref = self.coord_references[device]
                self.extracted_values['X_FRSTREF'] = x_frstref
                self.extracted_values['Y_FRSTREF'] = y_frstref
            else:
                Log.INFO(f"device={device} is not listed in Tesec WMC ref file={self.wmc_coordinates_ref_file}")
                # Util.dp_exit(1,f"device={device} is not listed in Tesec WMC ref file={self.wmc_coordinates_ref_file}") 
        else:
            Log.INFO("TPNO is not found or is None. Cannot proceed with x_frstref and y_frstref assignment.")
                    
    def perform_computations_and_initialize_wmc_attribute(self):
        # Check if all required extracted_values attributes are available to compute and place in the wmc_attribute dictionary
        # if all(attr_name in self.extracted_values and self.extracted_values[attr_name] is not None for attr_name in ['W_SIZE', 'CHIP_X', 'BLOCK_X', 'C_CODE']):
        try:
            # Convert extracted_values to appropriate numeric types if they are not None
            w_size = float(self.extracted_values.get('W_SIZE',0))
            chip_x = float(self.extracted_values.get('CHIP_X',0))
            chip_y = float(self.extracted_values.get('CHIP_Y',0))
            cx_addr = float(self.extracted_values.get('CX_ADDR',0))
            cy_addr = float(self.extracted_values.get('CY_ADDR',0))
            cdist_x = float(self.extracted_values.get('CDIST_X',0))
            cdist_y = float(self.extracted_values.get('CDIST_Y',0))
            cent_disty = float(self.extracted_values.get('CENT_DISTY', 0))
            cent_distx = float(self.extracted_values.get('CENT_DISTX', 0))
            c_code = int(self.extracted_values.get('C_CODE', 0))
            block_y = float(self.extracted_values.get('BLOCK_Y',0))
            block_x = float(self.extracted_values.get('BLOCK_X',0))
            x_first_act = int(self.extracted_values['X_FRSTACT'])
            x_first_ref = int(self.extracted_values.get('X_FRSTREF', 0))
            y_first_act = int(self.extracted_values['Y_FRSTACT'])
            y_first_ref = int(self.extracted_values.get('Y_FRSTREF', 0))
            # print(f"xfa={x_first_act}||xfr={x_first_ref}||yfa={y_first_act}||yfr={y_first_ref}")
            dp_center_x_offset = x_first_act - x_first_ref
            dp_center_y_offset = y_first_act - y_first_ref

            # Check if any attribute is None before performing further calculations
            # if None not in [w_size, chip_x, chip_y, cx_addr, cy_addr, cdist_x, cdist_y, cent_disty, cent_distx, block_y, block_x]:
            if w_size and chip_x and block_x and c_code:
                # wmc for exensio calculations
                wmc_wafer_size = float(w_size) / 1000
                wmc_die_width = float(chip_x) / 1000
                wmc_die_height = float(chip_y) / 1000
                x_center = cx_addr + (((-cdist_x - chip_x / 2) / 1000) / (chip_x / 1000))
                y_center = cy_addr - (((-cdist_y - chip_y / 2) / 1000) / (chip_y / 1000))
                # DP_ROW_OFFSET and DP_COL_OFFSET calculations
                dp_row_offset = int(((block_y / 2 * chip_y / 1000 + cent_disty) / (chip_y / 1000)) - 1)
                dp_col_offset = int(((block_x / 2 * chip_x / 1000 - cent_distx) / (chip_x / 1000)))
                dp_row_offset = round(dp_row_offset)  # Use round() to round to the nearest integer
                dp_col_offset = round(dp_col_offset)  # Use round() to round to the nearest integer
                wmc_reticle_row_offset = dp_row_offset % block_y
                wmc_reticle_col_offset = dp_col_offset % block_x
                self.calculated_values['DP_CENTER_X_OFFSET'] = dp_center_x_offset
                self.calculated_values['DP_CENTER_Y_OFFSET'] = dp_center_y_offset
                x_center_final = x_center - dp_center_x_offset
                y_center_final = y_center - dp_center_y_offset
                                
                self.wmc_attribute['WmcWaferSize'] = wmc_wafer_size
                self.wmc_attribute['WmcWaferUnits'] = "mm"
                self.wmc_attribute['WmcWaferFlat'] = "B"
                self.wmc_attribute['WmcFlatType'] = "N"
                self.wmc_attribute['WmcDieWidth'] = wmc_die_width
                self.wmc_attribute['WmcDieHeight'] = wmc_die_height
                self.wmc_attribute['WmcCenterX'] = round(x_center_final, 4)
                self.wmc_attribute['WmcCenterY'] = round(y_center_final, 4)
                self.wmc_attribute['WmcPositiveX'] = "R"
                self.wmc_attribute['WmcPositiveY'] = "D"
                self.wmc_attribute['WmcReticleRows'] = block_y
                self.wmc_attribute['WmcReticleCols'] = block_x
                self.wmc_attribute['WmcReticleRowOffset'] = dp_row_offset % block_y
                self.wmc_attribute['WmcReticleColOffset'] = dp_col_offset % block_x
            else:
                # Handle the case where one or more attributes are None
                # You can add appropriate error handling or fallback logic here
                Log.INFO("One or more attributes are None. Cannot perform calculations.")
        except (ValueError, TypeError) as e:
            Log.ERROR(f"An exception occured, Error in attribute conversion or calculations: {str(e)}", exc_info=True)
            # print(self.wmc_attribute)
                
    def get_wmc_in_dictionary(self):
        #self.get_wmc_reference() # get info from wmc reference file and put it in the dictionary
        #self.perform_computations_and_initialize_wmc_attribute()  # Perform computations before generating the dictionary

        if self.wmc_attribute:
            Log.INFO("Got and computed wmc info from FJM file.")
            return self.wmc_attribute
        else:
            Log.INFO("not able to get and calculated wmc info from FJM file.")
            return self.wmc_attribute
