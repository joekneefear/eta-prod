#!/usr/bin/env python3.12
#
# Hayden Mills	: original
# Eric Alfanta 	: modified to adapt DpLoad.pl loader

import os
import sys
import csv
#from multiprocessing import Pool
from index_mapper import index_mapper
import wire_bond
from collections import Counter
from datetime import datetime
import logging
import logging.handlers as handlers
import sys
import getopt

#may need config file to correctly determine bond count
bond_count = 9

def initLog(lgpath):
    currentTime = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    logger = logging.getLogger("sz_ft_wirebond_csv_to_iff.py")
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    logHandler = handlers.RotatingFileHandler(lgpath, maxBytes=500, backupCount=0)
    logHandler.setLevel(logging.INFO)
    logHandler.setFormatter(formatter)
    errlog = lgpath + "_err.log"
    errorHandler = handlers.TimedRotatingFileHandler(errlog, when="m", interval=1, backupCount=0)
    errorHandler.setLevel(logging.ERROR)
    errorHandler.setFormatter(formatter)
    consoleHandler = logging.StreamHandler(sys.stdout)
    consoleHandler.setFormatter(formatter)
    logger.addHandler(logHandler)
    logger.addHandler(errorHandler)
    logger.addHandler(consoleHandler)
    return logger

def main(files, outdir):
		#logger.info(f"log file={files}")
		with open(files,'r', encoding='utf-8', errors='ignore') as f:
			dat = f.readlines()
			tmp = []
			for rows in dat:
				tmp.append(rows.strip())
			raw_data = csv.reader(tmp,delimiter=',')

			headers = raw_data.__next__()
			lot_column = index_mapper('Lot ID',headers)
			record_column = index_mapper('Record Type',headers)
			data_start = index_mapper('Sample Data',headers)
			date_column = index_mapper('Record Timestamp',headers)
			recipe_column =  index_mapper('Process Program Name',headers)
			program_revision_column =  index_mapper('Program Last Edit Timestamp',headers)
			unit_id_column = index_mapper('Reserved',headers) + 1
			record_type_column = index_mapper('Record Type',headers)
			group_id_column = index_mapper('Bonder ID',headers)
			data_window =  index_mapper('Bonder Serial Number',headers)
			wedge =  index_mapper('Bondhead Number',headers)

			device_num_columns = index_mapper('Device Number',headers)
			wire_number_column = index_mapper('Wire Number',headers)
			bond_number_column = index_mapper('Bond Number',headers)
			lead_frame_column = index_mapper('Material ID',headers)

			bond_id_column = index_mapper('Bond Group ID',headers) 
			wire_feed_column = index_mapper('Wire Fed',headers) 
			bpm_peak_column = index_mapper('BPM Peak Status',headers) 
			bpm_us_column = index_mapper('BPM U/S Status',headers) 
			bpm_deform_column = index_mapper('BPM Deform. Status',headers) 
			bpm_frequency_column = index_mapper('BPM Frequency Status',headers) 
			alc_pull_column = index_mapper('ALC Pulltest Status',headers) 
			alc_pull_val_column = index_mapper('ALC Pulltest Value',headers)
			units_column = index_mapper('Sample Unit of Measure',headers)
			bond_position_column = index_mapper('Skip or Rework',headers)
			tester_column = index_mapper('Bonder ID',headers)
			handler_column = index_mapper('Bonder Serial Number',headers)
			operator_column = index_mapper('User ID',headers)

			wb = wire_bond.wire_bond()
			wb.logger = logger
			wb.filename = os.path.basename(files)
			wb.outputdir = outdir
			wb.basedir = os.path.dirname(files)
			limits = {}

			parameters_dict = {'BPMG-DFRM' : 'DFRM', 'BPMG-U/S' : 'U/S'}
			parameters = ['DFRM','U/S', 'ALCPT', 'FREQ']

			#get the counter data
			counter_dict = {}
			counter_data = csv.reader(tmp,delimiter=',')
			counter_dict['wedge change'] = []
			counter_dict['guide change'] = []
			counter_dict['wedge screw'] = []
			counter_dict['small tube'] = []
			counter_dict['large tube'] = []
			for rows in counter_data:
				record = rows[record_type_column]
				if record == 'COUNTERS':
					counter_dict['wedge change'].append(int(rows[group_id_column].split('=')[-1].strip()) - bond_count)
					counter_dict['guide change'].append(int(rows[data_window].split('=')[-1].strip()) - bond_count)
					counter_dict['wedge screw'].append(int(rows[wedge].split('=')[-1].strip()) - bond_count)
					counter_dict['small tube'].append(int(rows[operator_column].split('=')[-1].strip()) - bond_count)
					counter_dict['large tube'].append(int(rows[recipe_column].split('=')[-1].strip()) - bond_count)
			
			counter = 0
			curr_wire = ''
			curr_bond = ''
			#now get the raw data
			for rows in raw_data:
				try:
					wb.add_time(rows[date_column])
				except ValueError:
					#print(f'Bad Date in "{wb.filename}" column contains: {rows[date_column]}')
					logger.info(f'Bad Date in "{wb.filename}" column contains: {rows[date_column]}')
					return

				try:
					wb.add_recipe_rev(rows[program_revision_column])
					wb.add_recipe(rows[recipe_column])
					wb.add_lot(rows[lot_column])	
				except IndexError:
					pass				
				record = rows[record_type_column]
				if record == 'BOND':
					bond_position_string = rows[bond_position_column]
					bond_position_list = bond_position_string.split('=')[1].strip(' ()').split(',')
					wb.add_BOND(rows[device_num_columns],rows[wire_number_column],rows[bond_number_column],rows[bond_id_column], bond_position_list)	

				if record == 'ALCPT':
					if 'ALCPT' not in wb.limits.keys():
						wb.limits['ALCPT'] = {}
					wb.limits['ALCPT'][rows[bond_id_column]] = (('-1','-1','-1','-1','NA'),)
					wb.limits['ALCPT']['units'] = rows[units_column]
				
				if record == 'CONS':
					wb.bond_tool = rows[group_id_column].split('=')[-1].strip()
					wb.wire_spool = rows[data_window].split('=')[-1].strip()
				
				if record == 'COUNTER':
					counter += 1

				if record == 'BPARAM':
					#power config
					current_window = rows[wedge]
					current_window = current_window[current_window.find('{')+2:current_window.find('}')-1]
					current_window = current_window.split('),(')
					current_window = [tuple(items.split(',')) for items in current_window]
					bond_readpoints = [x[0] for x in current_window]
					bond_power = [x[1] for x in current_window]

					#force config
					current_window = rows[operator_column]
					current_window = current_window[current_window.find('{')+2:current_window.find('}')-1]
					current_window = current_window.split('),(')
					current_window = [tuple(items.split(',')) for items in current_window]
					bond_force = [x[1] for x in current_window]

				if record in parameters_dict.keys():
					current_window = rows[data_window]
					current_window = current_window[current_window.find('{')+2:current_window.find('}')-1]
					current_window = current_window.split('),(')
					current_window = [tuple(items.split(',')) for items in current_window]
					if parameters_dict[record] not in wb.limits.keys():
						wb.limits[parameters_dict[record]] = {}
					wb.limits[parameters_dict[record]][str.strip(rows[group_id_column].split('=')[1])] = current_window
					wb.limits[parameters_dict[record]]['units'] = rows[units_column]
					if record == 'BPMG-U/S':
						if 'FREQ' not in wb.limits.keys():
							wb.limits['FREQ'] = {}
						tmp = []
						for items in current_window:
							tmp.append((items[0],'-1','-1','-1','NA'))
						wb.limits['FREQ'][str.strip(rows[group_id_column].split('=')[1])] = tmp
						wb.limits['FREQ']['units'] = rows[units_column]

				if record in parameters:
					if curr_wire != rows[wire_number_column] or curr_bond != rows[bond_number_column]:
						curr_wire = rows[wire_number_column]
						curr_bond = rows[bond_number_column]
						counter_dict['wedge change'][counter] += 1
						counter_dict['guide change'][counter] += 1
						counter_dict['wedge screw'][counter] += 1
						counter_dict['small tube'][counter] += 1
						counter_dict['large tube'][counter]	+=	1	
					if record =='FREQ':
						wb.limits['FREQ']['units'] = rows[units_column]
					try:
						wb.add_tester(rows[tester_column])	
						wb.add_handler(rows[handler_column])
						wb.add_operator(rows[operator_column])
					except IndexError:
						pass											
					curr_wire = rows[wire_number_column]
					curr_bond = rows[bond_number_column]
					for data in wb.limits[record][rows[bond_id_column]]:
						wb.add_record(
									unitid = rows[unit_id_column],
									device_num = rows[device_num_columns],
									wire_num = rows[wire_number_column],
									bond_num = rows[bond_number_column],
									grp_id = rows[bond_id_column],
									LEADFRAME = rows[lead_frame_column],
									bond_group_id = rows[bond_id_column],
									wire_feed = rows[wire_feed_column],
									bond_start_time = bond_readpoints[0],
									bond_ramp_time = bond_readpoints[1],
									bond_hold_time = bond_readpoints[2],
									bond_start_power = bond_power[0],
									bond_ramp_power = bond_power[1],
									bond_hold_power = bond_power[2],
									bond_start_force = bond_force[0],
									bond_ramp_force = bond_force[1],
									bond_hold_force = bond_force[2],
									BPM_PEAK_STATUS = rows[bpm_peak_column],
									BPM_US_STATUS = rows[bpm_us_column],
									BPM_DEFORM_STATUS = rows[bpm_peak_column],
									BPM_FREQUENCY_STATUS = rows[bpm_frequency_column],
									ALC_PULLTEST_STATUS = rows[alc_pull_column],
									readpoint = rows[alc_pull_val_column] if record == 'ALCPT' else rows[data_start+int(data[0])-1],
									record = record,
									lower_lim = data[1],
									upper_lim = data[2],
									target_lim = data[3],
									time_readpoint = data[0],
									wedge_change = str(counter_dict['wedge change'][counter]),
									guide_change = str(counter_dict['guide change'][counter]),
									wedge_screw = str(counter_dict['wedge screw'][counter]),
									small_tube = str(counter_dict['small tube'][counter]),
									large_tube = str(counter_dict['large tube'][counter])
									)
							
			wb.recipe_rev=wb.recipe_rev.replace('/','-')
			wb.recipe_rev=wb.recipe_rev.replace(' ','_')
			wb.write_iff()
			#wb.gzip_iff()
			logger.info("###End Script###")

if __name__ == '__main__':
    outdir = ""
    logfile = ""
    argv = sys.argv[1:]
    infile = argv.pop(0)    
    
    try:
        opts, args = getopt.getopt(argv, "o:l:", ["out_dir=", "log_file="])
    except:
        print("Error in command line arguments!")

    for opt, arg in opts:
        if opt in ['-o', '--out_dir']:
            outdir = arg
        elif opt in ['-l', '--log_file']:
            logfile = arg
                 
    logger = initLog(logfile)
    
    logger.info("###Start Script###")
    logger.info(f"Input file={infile}")
    logger.info(f"Output directory={outdir}")
    logger.info(f"Log File={logfile}")
    
    main(infile,outdir)
    
