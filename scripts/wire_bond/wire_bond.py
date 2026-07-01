from datetime import datetime
import unit
import http.client
import json
from collections import Counter
import gzip
import shutil
#import subprocess
import os
import socket

class wire_bond:


	def __init__(self):
		self.data_class = 'ASY'
		self.site = 'CPA'
		self.fab = ''
		self.product = ''
		self.family = ''
		self.process = ''
		self.recipe = ''
		self.recipe_rev = ''
		self.processing_step = 'WIREBOND'
		self.retest_code = 'TST'
		self.lot = ''
		self.SOURCE_LOT = ''
		self.filename = ''
		self.limits = {}
		self.window = {}
		self.data = []
		self.iff = []
		self.bond_group = {}
		self.times = []
		self.technology = ''
		self.package = ''
		self.lot_class = ''
		self.alt_product = ''
		self.tester = ''
		self.handler = ''
		self.operator = ''
		self.bond_tool = ''
		self.wire_spool = ''
		self.outputdir = ''
		self.basedir = ''
		self.logger = ''

	def get_bond_data(self, device_number, wire_number, bond_number, key : str):
		return self.bond_group[device_number][wire_number][bond_number][key]['BOND_POSITION_X'],\
				self.bond_group[device_number][wire_number][bond_number][key]['BOND_POSITION_Y'],\
				self.bond_group[device_number][wire_number][bond_number][key]['BOND_POSITION_Z'],\
				self.bond_group[device_number][wire_number][bond_number][key]['BOND_POSITION_T']

	def add_time(self, record : str):
		date_obj = datetime.fromisoformat(record)
		self.times.append(date_obj)

	def add_BOND(self, device_number, wire_number, bond_number, key : str, val : list):
		if device_number not in self.bond_group.keys():
			self.bond_group[device_number] = {}
		if wire_number not in self.bond_group[device_number].keys():
			self.bond_group[device_number][wire_number] = {}
		if bond_number not in self.bond_group[device_number][wire_number].keys():
			self.bond_group[device_number][wire_number][bond_number] = {}
		if key not in self.bond_group[device_number][wire_number][bond_number].keys():
			self.bond_group[device_number][wire_number][bond_number][key]= {}
		self.bond_group[device_number][wire_number][bond_number][key]['BOND_POSITION_X'] = val[0]
		self.bond_group[device_number][wire_number][bond_number][key]['BOND_POSITION_Y'] = val[1]
		self.bond_group[device_number][wire_number][bond_number][key]['BOND_POSITION_Z'] = val[2]
		self.bond_group[device_number][wire_number][bond_number][key]['BOND_POSITION_T'] = val[3]

	def add_record(
				self, 
				unitid : str, 
				device_num : str, 
				wire_num : str, 
				bond_num : str, 
				grp_id : str,
				LEADFRAME : str,
				bond_group_id : str,
				wire_feed : str,
				bond_start_time : str,
				bond_ramp_time : str,
				bond_hold_time : str,
				bond_start_power : str,
				bond_ramp_power : str,
				bond_hold_power : str,
				bond_start_force : str,
				bond_ramp_force : str,
				bond_hold_force: str,
				BPM_PEAK_STATUS : str,
				BPM_US_STATUS : str,
				BPM_DEFORM_STATUS : str,
				BPM_FREQUENCY_STATUS : str,
				ALC_PULLTEST_STATUS : str,
				readpoint : str,
				record : str,
				lower_lim : str,
				upper_lim : str,
				target_lim : str,
				time_readpoint,
				wedge_change : str,
				guide_change : str,
				wedge_screw : str,
				small_tube : str,
				large_tube : str
				):
		new_unit_data = unit.unit_level_data(
				unitid,
				device_num, 
				wire_num, 
				bond_num, 
				grp_id,
				LEADFRAME,
				bond_group_id,
				wire_feed,
				bond_start_time,
				bond_ramp_time,
				bond_hold_time,
				bond_start_power,
				bond_ramp_power,
				bond_hold_power,
				bond_start_force,
				bond_ramp_force,
				bond_hold_force,
				BPM_PEAK_STATUS,
				BPM_US_STATUS,
				BPM_DEFORM_STATUS,
				BPM_FREQUENCY_STATUS,
				ALC_PULLTEST_STATUS,
				lower_lim,
				upper_lim,
				target_lim,
				time_readpoint,
				wedge_change,
				guide_change,
				wedge_screw,
				small_tube,
				large_tube)
		new_unit_data.measurements[record] = readpoint
		new_unit_data.BOND_POSITION_X, \
		new_unit_data.BOND_POSITION_Y, \
		new_unit_data.BOND_POSITION_Z, \
		new_unit_data.BOND_POSITION_T = self.get_bond_data(
														new_unit_data.device_num,
														new_unit_data.wire_num,
														new_unit_data.bond_num,
														new_unit_data.grp_id,
														)
		self.data.append(new_unit_data)				



	def get_metadata(self, lotid : str):
		etl_host = socket.gethostname()
		host = ""
		
		self.logger.info(f'Lot ID = {lotid}')		

		if etl_host.lower == "usaz15ls082.onsemi.com" or etl_host.lower == "usaz15ls083.onsemi.com":
			self.logger.info(f'INFO: Using ERT Production.')
			host = 'globmfgapp.onsemi.com:61050' #ERT PROD
		else:
			self.logger.info(f'INFO: Using ERT Quality Assurance.')
			host = 'usaz15ls120.onsemi.com:61050' #ERT QA 

		onLot2 = f'/exensioreftables-ws/api/onlotprod/bylotid/{lotid}'
		c = http.client.HTTPConnection(host)
		c.request("GET",onLot2, headers={"accept":"*/*"})
		resp = c.getresponse()

		data = json.loads(resp.read())

		self.product = data['onProd']['product'] or 'N/A'
		self.SOURCE_LOT = data['onLot']['sourceLot'] or lotid
		self.fab = data['onLot']['fab'] or 'N/A'
		self.family = data['onProd']['family'] or 'N/A'
		self.process = data['onProd']['process'] or 'N/A'
		self.technology = data['onProd']['technology'] or 'N/A'
		self.package = data['onProd']['package'] or 'N/A'
		self.lot_class = data['onLot']['lotType'] or 'N/A'
		self.alt_product = data['onLot']['alternateProduct'] or 'N/A'
		self.status = data['onLot']['status']


	def add_recipe_rev(self,  val):
		if self.recipe_rev == '':
			self.recipe_rev = val

	def add_recipe(self,  val):
		if self.recipe == '':
			self.recipe = val

	def add_lot(self,  val):
		if self.lot == '':
			self.lot = val
	
	def add_tester(self,  val):
		if self.tester == '':
			self.tester = val	

	def add_handler(self,  val):
		if self.handler == '':
			self.handler = val			

	def add_operator(self,  val):
		if self.operator == '':
			self.operator = val
	
	def make_iff(self):
		self.get_metadata(self.lot)
		self.iff =[
			'<HEADER>',
			'VERSION=1.0',
			f"CREATION_DATE={datetime.now().strftime('%Y/%m/%d %H:%M:%S')}",
			'PROGRAM_CLASS=43',
			f'PROGRAM={self.data_class}_{self.site}_{self.product}_{self.recipe}:{self.recipe_rev}:{self.processing_step}:{self.retest_code}',
			'RELEASE=N/A',
			f'REVISION=N/A',
			f'RECIPE={self.recipe}',
			f'FAB={self.fab}',
			f'TECHNOLOGY={self.technology}',
			f'FAMILY={self.family}',
			f'PROCESS={self.process}',
			f'PRODUCT={self.product}',
			f'PACKAGE={self.package}',
			'STEP=WIREBOND',
			'STAGE=N/A',
			'STEP_GRP1=N/A',
			'STEP_GRP2=N/A',
			'STEP_GRP3=N/A',
			f'LOT={self.lot}',
			f'SOURCE_LOT={self.SOURCE_LOT  + ".S"}',
			f'LOT_CLASS={self.lot_class}',
			'DATE_CODE=N/A',
			f'EQUIP1_ID={self.tester or "N/A"}',
			f'EQUIP2_ID={self.handler or "N/A"}',
			f'EQUIP3_ID=N/A',	# Probe Card
			f'EQUIP4_ID={self.alt_product}',
			f'EQUIP5_ID={self.recipe_rev}',
			'EQUIP6_ID=CPA:SUZHOU BACKEND (BSL)',
			'CFG_TESTER_TYPE=N/A',
			f'INDEX1={self.bond_tool}',
			f'INDEX2={self.wire_spool}',
			f'OPERATOR={self.operator}',
			f'START_TIME={self.times[0]}',
			f'END_TIME={self.times[-1]}',
			f'DEVICE_COUNT={len(Counter([x.dbcid for x in self.data]))}',
			'</HEADER>',
			'<WMAP>',
			'</WMAP>',
			'<WAFER>',
			f'WAFER_ID={self.SOURCE_LOT}_00',
			'WAFER_NUMBER=00',
			'</WAFER>',
			'<BIN>',
			'</BIN>',
			'<HBIN>',
			'</HBIN>',
			'<PAR>',
			'1,DATA,N/A,N/A',
			'</PAR>',
			'<DATA>'
		]
		part_index = 1
		for units in self.data:
			for results in units.measurements:
				self.iff.append(f'PART_INDEX={part_index}')
				self.iff.append('DIE_X=N/A')
				self.iff.append('DIE_Y=N/A')
				self.iff.append(f'DBCID={units.dbcid}')
				self.iff.append(f'DEVICE_NUMBER={units.device_num}')
				self.iff.append(f'WIRE_NUMBER={units.wire_num}')
				self.iff.append(f'BOND_NUMBER={units.bond_num}')
				self.iff.append(f"LEADFRAME_ID={units.LEADFRAME}")
				self.iff.append(f"BOND_GROUP={units.grp_id}")
				self.iff.append(f"WIRE_FEED={units.wire_feed}")
				self.iff.append(f"WEDGE_CHANGE={units.wedge_change}")
				self.iff.append(f"GUIDE_CHANGE={units.guide_change}")
				self.iff.append(f"WEDGE_SCREW={units.wedge_screw}")
				self.iff.append(f"SMALL_TUBE={units.small_tube}")
				self.iff.append(f"LARGE_TUBE={units.large_tube}")
				self.iff.append(f"START_RAMP_TIME={units.bond_start_time}")
				self.iff.append(f"BOND_RAMP_TIME={units.bond_ramp_time}")
				self.iff.append(f"BOND_HOLD_TIME={units.bond_hold_time}")
				self.iff.append(f"START_POWER={units.bond_start_power}")
				self.iff.append(f"BOND_POWER={units.bond_ramp_power}")
				self.iff.append(f"POWER={units.bond_hold_power}")
				self.iff.append(f"START_FORCE={units.bond_start_force}")
				self.iff.append(f"BOND_FORCE={units.bond_ramp_force}")
				self.iff.append(f"FORCE={units.bond_hold_force}")
				self.iff.append(f"BPM_PEAK_STATUS={units.BPM_PEAK_STATUS}")
				self.iff.append(f"BPM_US_STATUS={units.BPM_US_STATUS}")
				self.iff.append(f"BPM_FREQUENCY_STATUS={units.BPM_FREQUENCY_STATUS}")
				self.iff.append(f"ALC_PULLTEST_STATUS={units.ALC_PULLTEST_STATUS}")
				self.iff.append(f"BOND_POSITION_X={units.BOND_POSITION_X}")
				self.iff.append(f"BOND_POSITION_Y={units.BOND_POSITION_Y}")
				self.iff.append(f"BOND_POSITION_Z={units.BOND_POSITION_Z}")
				self.iff.append(f"BOND_POSITION_T={units.BOND_POSITION_T}")
				self.iff.append(f"MEASUREMENT={results}")
				self.iff.append(f"UNITS={self.limits[results]['units']}")
				self.iff.append(f"TIME_READPOINT={units.time_readpoint}")
				self.iff.append(f"LOWER_LIMIT={units.lower_limit}")
				self.iff.append(f"UPPER_LIMIT={units.upper_limit}")
				self.iff.append(f"TARGET_LIMIT={units.target_limit}")
				self.iff.append(units.measurements[results])
				part_index += 1
					

		self.iff.append('</DATA>')

	def print_iff(self):
		self.make_iff()
		print('\n'.join(self.iff))


	#def write_iff(self):
	#	self.make_iff()
	#	self.logger.info(f'Output IFF = {self.outputdir}/{self.filename}.iff')
	#	with open(f'{self.outputdir}/{self.filename}.iff', 'w', encoding='utf-8') as f:
	#		f.write('\n'.join(self.iff))
	#		f.write('\n')


	def write_iff(self):
		self.make_iff()
		output_path = ""
		if self.matches_pattern(self.status):
			self.logger.info(f'Good! Metadata found = {self.status}')
			output_path = f'{self.outputdir}/PRODUCTION/{self.filename}.iff.gz'
		else:
			self.logger.info(f'Bad! Metadata not found = {self.status}')
			output_path = f'{self.outputdir}/SANDBOX/{self.filename}.iff.gz'

		self.logger.info(f'Output file = {output_path}')

		with gzip.open(output_path, 'wt', encoding='utf-8') as f:
			f.write('\n'.join(self.iff))
			f.write('\n')	

	#def gzip_iff(self):
	#	outdirectory = self.outputdir
	#	basedir = self.basedir
	#	ifffile = outdirectory + "/" + self.filename + ".iff"
	#	gzifffile = outdirectory + "/" + self.filename + ".iff.gz"

	#	with open(ifffile, 'rb') as f_in:
	#		with gzip.open(gzifffile, 'wb') as f_out:
	#			shutil.copyfileobj(f_in, f_out)
	#	os.remove(ifffile)

	#def gzip_iff(self):
	#	self.make_iff()
	#	outdirectory = self.outputdir
	#	ifffile = self.filename + ".iff"
	#	iff_file = os.path.join(outdirectory, ifffile)
	#	subprocess.run(["gzip", iff_file])

	def matches_pattern(self,input_string):
		valid_patterns = {
			"LOTG_MFGLOT_MES_LTM_DW",
			"MANUAL",
			"LOTG_MFGLOT_LTM",
			"LOTG_MFGLOT_MES_DW",
			"LOTG_DW",
			"FOUND",
			"LOTG_LTM_DW",
			"LOTG_MES_LTM_DW",
			"LOTG",
			"LOTG_MFGLOT",
			"LOTG_MES_DW",
			"LOTG_MFGLOT_DW"
		}
		return input_string in valid_patterns
