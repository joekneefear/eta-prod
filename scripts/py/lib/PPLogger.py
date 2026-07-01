"""

SYNOPSIS

DESCRIPTION
    refdb.pp_log preprocessing logger object
AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-Mar-31 - jgarcia - initial

LICENSE
    (C) onsemi 2025 All rights reserved.
"""

from dataclasses import dataclass, field
from datetime import datetime
from zoneinfo import ZoneInfo
import hashlib
import re
import yaml
from sqlalchemy import Table, Column, Integer, String, DateTime, MetaData, select
from sqlalchemy.orm import sessionmaker
from lib.Data.Models.PPLog import PPLog
from lib.Log import Log
from lib.DbConnection import DbConnection
from lib.DbConnectionFactory import DbConnectionFactory
import hashlib

@dataclass
class PPLogger:
    _LOT: str = ''
    _SOURCE_LOT: str = ''
    _ENV: str = ''
    _PROC_CODE: str = ''
    _RAW_FILE: str = ''
    _OUT_DIR: str = ''
    _LOG_MSG: str = ''
    _MAP_ID: str = ''
    _WAF_NUM: str = ''
    _WAF_NUM_SL: str = ''
    _PROG_CLASS: str = ''
    _SITE: str = ''
    _PROG_NAME: str = ''
    _LIMIT_FILE: str = ''
    _EXT: str = ''
    _MD5: str = ''
    _PATH: str = ''
    _SCRIPT: str = ''
    _model: object = None
    _header: object = None
    _ISTOBELOG: bool = False
    _waferFlag: bool = False
    _initialized: bool = field(default=False, init=False)
    exclude_patterns: list = field(default_factory=list, init=False)
    db_session = None

    def __post_init__(self):
        if not self._initialized:
            self._initialized = True
            self.load_config()
    
    def set_db(self, db_session):
        self.db_session = db_session   
    
    def load_config(self):
        with open('/export/home/dpower/project/scripts/py/resources/pplogger_exclude_patterns.yaml', 'r') as file:
        # with open('/export/home/dpower/project/work/jgarcia/eta-master/scripts/py/resources/pplogger_exclude_patterns.yaml', 'r') as file:
            config = yaml.safe_load(file)
            self.exclude_patterns = config.get('exclude_patterns', [])

    def set_to_be_logged(self, flag: bool):
        self._ISTOBELOG = flag

    def set_wafer_flag(self, flag: bool):
        self._waferFlag = flag

    def set_model_header(self, model):
        if self._initialized:
            self._model = model
            self._header = model.header
            
    def set_lot(self, lot):
        if self._initialized:
            self._LOT = lot if lot else self._LOT
            return self._LOT

    def set_script(self, script):
        if self._initialized:
            self._SCRIPT = script if script else self._SCRIPT
            return self._SCRIPT

    def set_source_lot(self, source_lot):
        if self._initialized:
            self._SOURCE_LOT = source_lot if source_lot else self._SOURCE_LOT
            return self._SOURCE_LOT

    def set_env(self, site, tester=''):
        if self._initialized:
            if tester:
                if tester in site:
                    env = site
                else:
                    env = f"{site}_{tester}"
            else:
                env = site

            self._ENV = env
            return self._ENV

    def set_proc_code(self, proc_code):
        if self._initialized:
            self._PROC_CODE = proc_code if proc_code else self._PROC_CODE
            return self._PROC_CODE

    def set_raw_file(self, raw_file):
        if self._initialized:
            self._RAW_FILE = raw_file if raw_file else self._RAW_FILE
            return self._RAW_FILE

    def set_out_dir(self, out_directory):
        if self._initialized and self._OUT_DIR == "":
            self._OUT_DIR = out_directory if out_directory else self._OUT_DIR
            return self._OUT_DIR

    
    def set_log_msg(self, log_msg, force=False):
        if self._initialized:
            # Only persist messages that match specific criteria OR are forced
            should_log = False
            
            # 0. EXCLUSION: Skip logging if specific patterns found (unless forced)
            if not force and re.search(r'pandas', log_msg, re.IGNORECASE):
                should_log = False
            
            # 1. Always log errors and warnings
            elif force or re.search(r'ERROR|WARNING|fail|exception', log_msg, re.IGNORECASE):
                should_log = True
                
            # 2. Log specific important operational events (whitelist approach)
            # Added 'metadata' as a general catch-all for any metadata related logs
            elif re.search(r'lot lookup|files processed|metadata', log_msg, re.IGNORECASE):
                should_log = True
                
            if should_log:
                if self._LOG_MSG:
                    # Avoid duplicate adjacent messages
                    if not self._LOG_MSG.endswith(log_msg):
                         self._LOG_MSG += " -- " + log_msg
                else:
                    self._LOG_MSG = log_msg
                
                # Preventive truncation at 1500 chars to avoid ORA-12899 (multibyte expansion)
                if self._LOG_MSG and len(self._LOG_MSG) > 1500:
                    self._LOG_MSG = self._LOG_MSG[:1497] + "..."

        return self._LOG_MSG


    def set_map_id(self, map_id):
        if self._initialized:
            self._MAP_ID = map_id if map_id else self._MAP_ID
            return self._MAP_ID
        
    def set_waf_num(self, waf_num, site=None):
        if self._initialized:
            if site is not None:
                self._WAF_NUM = waf_num
            else:
                source_lot = self._SOURCE_LOT.rstrip('.S')
                if waf_num:
                    if source_lot and self._waferFlag:
                        self._WAF_NUM = f"{source_lot}_{waf_num}"
                    else:
                        self._WAF_NUM = f"{self._LOT}_{waf_num}"
            return self._WAF_NUM


    def set_waf_num_sl(self, waf_num):
        if self._initialized:
            source_lot = self._SOURCE_LOT.rstrip('.S')
            self._WAF_NUM_SL = f"{source_lot}_{waf_num}" if waf_num else self._WAF_NUM_SL
            return self._WAF_NUM_SL

    def set_program_class(self, prog_class):
        if self._initialized:
            self._PROG_CLASS = prog_class if prog_class else self._PROG_CLASS
            return self._PROG_CLASS

    def set_site(self, site):
        if self._initialized:
            self._SITE = str(site) if site else self._SITE
            return self._SITE

    def set_program_name(self, prog_name):
        if self._initialized:
            self._PROG_NAME = prog_name if prog_name else self._PROG_NAME
            return self._PROG_NAME

    def set_limit_file(self, limit_file):
        if self._initialized:
            if self._LIMIT_FILE == '':
                self._LIMIT_FILE = limit_file if limit_file else self._LIMIT_FILE
            return self._LIMIT_FILE

    def set_ext(self, ext):
        if self._initialized:
            self._EXT = ext if ext else self._EXT
            return self._EXT

    def set_md5(self, md5=None):
        if self._initialized:
            if md5:
                self._MD5 = md5
            else:
                try:
                    ctx = hashlib.md5()
                    with open(self._RAW_FILE, 'rb') as file:
                        ctx.update(file.read())
                        self._MD5 = ctx.hexdigest()
                except FileNotFoundError:
                    Log.ERROR(f"File not found: {self._RAW_FILE}")
                    self._MD5 = None
                except Exception as e:
                    Log.ERROR(f"An error occurred: {e}")
                    self._MD5 = None
            return self._MD5

    def set_path(self, path):
        if self._initialized:
            self._PATH = path if path else self._PATH
            return self._PATH

    def pp_log_exit(self, proc_code: str):
        if self._initialized:
            self._PROC_CODE = proc_code
            if self._header:
                self._LOT = self._header.LOT
                self._SOURCE_LOT = self._header.SOURCE_LOT
                if not self._PROG_CLASS.strip():
                    self._PROG_CLASS = self._header.PROGRAM_CLASS
                self._PROG_NAME = self._header.PROGRAM

            if self._ISTOBELOG:
                # print("IM HERE")
                # print(f"LOGM={self._LOG_MSG}")
                self.insert_db(db_session=self.db_session)
            else:
                Log.INFO("Not to be logged")

    def get_datetime(self):
        now = datetime.now()
        return now.strftime("%Y/%m/%d %H:%M:%S")

    def parse_infile(self):
        path = ''
        rawfile = self._RAW_FILE
        ext = ''

        if not rawfile.endswith('.gz'):
            if re.search(r'.*\.SPD;.*\.LSR', rawfile, re.IGNORECASE):
                rawfile = re.sub(r';.*', '', rawfile)
                path, rawfile, ext = re.match(r'(.*)/(.*)\.(.*)', rawfile).groups()
                ext = 'LSR;SPD'
            else:
                path, rawfile, ext = re.match(r'(.*)/(.*)\.(.*)', rawfile).groups()
        else:
            path, rawfile, ext = re.match(r'(.*)/(.*)\.(.*)\.gz$', rawfile).groups()

        if not self._ENV:
            self._ENV = re.search(r'/data/([^/]*)', path).group(1)

        if re.search(r'(.*)_MD5-(.*)', ext):
            ext, md5 = re.match(r'(.*)_MD5-(.*)', ext).groups()
            self._MD5 = md5

        self._PATH = path
        self._RAW_FILE = rawfile
        self._EXT = ext

    def get_errcode_yaml(self, info):
        info = info.strip()
        with open('/export/home/dpower/project/scripts/lib/PPLOG/error_codes.yml', 'r') as file:
            error_codes = yaml.safe_load(file)

        for code, pattern in error_codes.items():
            if re.search(pattern, info, re.IGNORECASE):
                return code
        return ''

    def insert_db(self, db_session=None):
        
        ERR_CODE = ""
        time_zone = "America/New_York"
        date_us = datetime.now(ZoneInfo("America/Phoenix"))
        
        if self._SCRIPT == "fcs_metadataVerifier.py":
            ERR_CODE = "E0000"
            if not re.match(r"0|10|1011|100|4", self._PROC_CODE):
                self._OUT_DIR = "NotProcessed"
            else:
                ERR_CODE = self.get_errcode_yaml(self._LOG_MSG)
        else:
            if re.match(r"PRODUCTION|QDE|SANDBOX|ReworkFiles|inbox", self._OUT_DIR, re.IGNORECASE):
                ERR_CODE = self.get_errcode_yaml(self._LOG_MSG)
            else:
                ERR_CODE = "E0000"

        self.parse_infile()

        if self._LOG_MSG:
            self._LOG_MSG = self._LOG_MSG.replace("'", "")
            self._LOG_MSG = self._LOG_MSG[:1500]
            # print(f"TEST2=>>>>>>{self._LOG_MSG}<<<<<<")

        if not self._SITE:
            self._SITE = self._ENV[:2].upper()

        # if not self._MD5 and self._RAW_FILE:
        #     with open(self._RAW_FILE, 'rb') as file:
        #         self._MD5 = hashlib.md5(file.read()).hexdigest()

        if self._SITE not in ["ME", "MT", "SL"]:
            time_zone = "Asia/Hong_Kong"

        date_asia = datetime.now(ZoneInfo("Asia/Hong_Kong"))
        
        pp_log_entry = PPLog(
            LOT=self._LOT,
            ENVIRONMENT=self._ENV,
            PROCESS_DATETIME=date_us,
            PROCESS_CODE=self._PROC_CODE,
            FILE_NAME=self._RAW_FILE,
            OUTPUT_DIRECTORY=self._OUT_DIR,
            LOG_MESSAGE=self._LOG_MSG,
            INSERT_ID='',
            MAP_ID=self._MAP_ID,
            WAFER_NUM=self._WAF_NUM,
            ERROR_CODE=ERR_CODE,
            PROGRAM_CLASS=self._PROG_CLASS,
            SITE=self._SITE,
            PROCESS_DATETIME_ADJUST=date_asia,
            LIMIT_FILE_NAME=self._LIMIT_FILE,
            PROGRAM_NAME=self._PROG_NAME,
            EXTENSION=self._EXT,
            MD5=self._MD5,
            PATH=self._PATH,
            SCRIPT=self._SCRIPT
        )
        if(self.db_session):
            try:
                self.db_session.add(pp_log_entry)
                self.db_session.commit()
                Log.INFO("Successfully logged to refdb.pp_log")
            except Exception as e:
                self.db_session.rollback()
                Log.ERROR(f"Failed to log to refdb.pp_log: {e}")
            finally:
                self.db_session.close()
        else:
            try:
                db_type = 'oracle'
                db_connection = DbConnectionFactory.create_db_connection(db_type)
                session = db_connection.get_session()
                session.add(pp_log_entry)
                session.commit()
                Log.INFO("Successfully logged to refdb.pp_log")
            except Exception as e:
                session.rollback()
                Log.ERROR(f"Failed to log to refdb.pp_log: {e}")
            finally:
                session.close()
                
            