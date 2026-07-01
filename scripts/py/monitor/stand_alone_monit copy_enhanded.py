import os
import time
import glob
import shlex
import subprocess
import threading
from logging.handlers import RotatingFileHandler
import yaml
import sys
import json
from datetime import datetime
import time
# Import Log and Util classes from the lib module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from lib import Log
from lib import Util
import re

# Environment Configuration
LOG_FILE = os.getenv('LOG_FILE', '/export/home/dpower/project/log/fcs_preprocessor_monitor.log')
YAML_FILE = os.getenv('YAML_FILE', '/export/home/dpower/jag/eta_master/scripts/py/monitor/preprocessor_monitor.yml')
STATUS_FILE = os.getenv('STATUS_FILE', '/export/home/dpower/jag/eta_master/scripts/py/monitor/status.json')

# Configure logging
Log.configure_logger(log_file=LOG_FILE)
logger = Log.get_logger()

# Monitor class
class Monitor:
    _instance = None

    def __new__(cls, YAML_FILE):
        if cls._instance is None:
            cls._instance = super(Monitor, cls).__new__(cls)
            cls._instance._initialize(YAML_FILE)
        return cls._instance

    def _initialize(self, YAML_FILE):
        self.status_lock = threading.RLock()  # Initialize status_lock first
        self.not_running_start_time = {}
        self.yaml_data = Util.load_yaml(YAML_FILE)
        self.restart_threshold = self.yaml_data['auto_restart_threshold']
        self.sleep_time = self.yaml_data['monitor_sleep_time']
        self.data_list = self.build_preprocessing_info()
        self.save_status_to_json()
        self.not_running_list = []

    def parse_mgr_file(self, file_path):
        if not os.path.isfile(file_path):
            raise ValueError(f"{file_path} does not exist.")
        parsed_list = []
        sequence = 1
        with open(file_path, 'r') as file:
            for line in file:
                if line.startswith('#') or '#' in line:
                    continue
                parts = [part for part in line.replace(':', ' ').split() if part]
                if not parts:
                    continue
                try:
                    line_dict = {
                        'sequence': sequence,
                        'cfg': parts[0],
                        'sleep': parts[parts.index('-sleep') + 1] if '-sleep' in parts else None,
                        'group': parts[-1]
                    }
                except (IndexError, ValueError):
                    raise ValueError(f"Line {sequence} is not formatted correctly.")
                parsed_list.append(line_dict)
                sequence += 1
        return parsed_list

    def parse_cfg_file(self, cfg_file):
        if Util.check_file_exists(cfg_file):
            try:
                with open(cfg_file, 'r') as file:
                    for line in file:
                        if line.startswith('#'):
                            continue
                        line = line.strip()
                        if not line:
                            continue

                        # Extract staging folder, file type, log file, and source folder
                        parts = re.split(r'[:\s]', line)
                        staging_folder = parts[0] if parts else None
                        file_type = parts[2] if len(parts) > 1 else None
                        logfile_value = self.get_value_after_string(line, ["--log", "-log", "--logfile", "-logfile", "--log_file", "-log_file"])
                        source_folder = self.get_value_after_string(line, ["--inbox", "-inbox", "--source", "-source"])

                        # Resolve variables in paths if necessary
                        if staging_folder:
                            staging_folder = self.resolve_variable(staging_folder)
                        if logfile_value:
                            logfile_value = self.resolve_variable(logfile_value)
                        if source_folder:
                            source_folder = self.resolve_variable(source_folder)

                        # Use source_folder to replace staging_folder if staging_folder is 'NA', 'N/A', 'na', or blank
                        if not staging_folder or staging_folder.lower() in ['na', 'n/a', '']:
                            if source_folder:
                                staging_folder = source_folder
                            else:
                                Log.ERROR(f'No staging folder found, pls check the cfg file {cfg_file}')
                                Util.dp_exit(1,f"No staging folder found, could be cfg file is malformed {cfg_file}")

                        return staging_folder, file_type, logfile_value
            except FileNotFoundError:
                Log.INFO(f"CFG File {cfg_file}")
                Util.dp_exit(1,"ERROR malformed cfg file={cfg_file}")
        else:
            Log.INFO(f'cfg file did not exists={cfg_file}')
            Util.dp_exit(1, 'cfg not found')

    def resolve_variable(self, path):
        # Resolve variables in the path
        if path.startswith('$DPDATA'):
            path = path.replace('$DPDATA', self.yaml_data['DPDATA'])
        elif path.startswith('$REFERENCE_DATA_DIR'):
            path = path.replace('$REFERENCE_DATA_DIR', self.yaml_data['REFERENCE_DATA_DIR'])
        elif path.startswith('$DPLOG'):
            path = path.replace('$DPLOG', self.yaml_data['DPLOG'])
        return path

    def get_value_after_string(self, s, targets):
        # Extract value after specified targets
        parts = re.split(r'[\s=]', s)
        for i, part in enumerate(parts):
            if part in targets and i + 1 < len(parts):
                return parts[i + 1]
        return None



    # def parse_cfg_file(self, cfg_file):
    #     try:
    #         with open(cfg_file, 'r') as file:
    #             for line in file:
    #                 if line.startswith('#') or '#' in line:
    #                     continue
    #                 columns = line.split(':')
    #                 staging_folder = columns[0].strip() if len(columns) > 0 else None
    #                 if staging_folder and staging_folder not in ['NA', 'N/A']:
    #                     if staging_folder.startswith('$DPDATA'):
    #                         staging_folder = staging_folder.replace('$DPDATA', self.yaml_data['DPDATA'])
    #                     if staging_folder.startswith('$REFERENCE_DATA_DIR'):
    #                         staging_folder = staging_folder.replace('$REFERENCE_DATA_DIR', self.yaml_data['REFERENCE_DATA_DIR'])
    #                 file_type = columns[2].strip() if len(columns) > 2 else None
    #                 logfile_value = self.get_value_after_string(columns[3], ["log", "log_file", "logfile"]) if len(columns) > 2 else None
    #                 if logfile_value and logfile_value.startswith('$DPLOG'):
    #                     logfile_value = logfile_value.replace('$DPLOG', self.yaml_data['DPLOG'])
    #                 if logfile_value and logfile_value.startswith('$DPDATA'):
    #                     logfile_value = logfile_value.replace('$DPDATA', self.yaml_data['DPDATA'])
    #                 source_folder = self.get_value_after_string(columns[3], ["source", "inbox"]) if len(columns) > 2 else None
    #                 if source_folder and source_folder.startswith('$DPDATA'):
    #                     source_folder = source_folder.replace('$DPDATA', self.yaml_data['DPDATA'])
    #                 if not staging_folder or staging_folder in ['NA', 'N/A'] and source_folder:
    #                     staging_folder = source_folder
    #                 return staging_folder, file_type, logfile_value
    #     except FileNotFoundError:
    #         Log.INFO(f"File {cfg_file} not found.")
    #         return None, None, None

    # def get_value_after_string(self, s, targets):
    #     s = s.replace('=', ' ')
    #     parts = s.split()
    #     for i, part in enumerate(parts):
    #         if any(target in part for target in targets) and i + 1 < len(parts):
    #             return parts[i + 1]
    #     return None

    # def get_file_type(self, filename):
    #     known_compressed_types = ['gz', 'zip']
    #     parts = filename.split('.')
    #     if len(parts) > 2 and parts[-1] in known_compressed_types:
    #         file_type = parts[-2]
    #     else:
    #         file_type = parts[-1] if len(parts) > 1 else None
    #     return file_type

    def build_preprocessing_info(self):
        mgr_file = self.yaml_data['mgr_file']
        data_list = []
        is_running = False
        pid_status = ""
        not_running_timestamp = 0
        mgr_data_lines = self.parse_mgr_file(mgr_file)
        for preprocess_cfg in mgr_data_lines:
            cfg_file = preprocess_cfg['cfg']
            if cfg_file:
                cfg_file = cfg_file.replace('$DPLOAD', self.yaml_data['DPLOAD'])
                staging_folder, file_type, logfile = self.parse_cfg_file(cfg_file)
                file_count = Util.count_files_in_folder(staging_folder, file_type)
                not_running_timestamp = None
            # if staging_folder is None and file_type is None and logfile is None:
            #     continue
                pid_file = cfg_file + '.pid'
                Log.INFO(f'PID_FILE={pid_file}')
                if Util.check_file_exists(pid_file):
                    pid = Util.get_pid_from_file(pid_file)
                    if pid:
                        is_running = Util.is_pid_running(pid)
                        pid_status = "Running"
                        not_running_timestamp = None
                    else:
                        Log.INFO(f'Please check has pid file but no PID..')
                        pid_status = "Not Running"
                        not_running_timestamp = Util.get_current_timestamp(0)
                else:
                    Log.INFO(f'PID file = {pid_file} not found')
                    pid_status = "Not Running"
                    not_running_timestamp = Util.get_current_timestamp(0)
                
                data_list.append({
                    "sequence": preprocess_cfg['sequence'],
                    "cfg_file": cfg_file,
                    "log_file": logfile,
                    "sleep_time": int(preprocess_cfg['sleep']) if preprocess_cfg['sleep'] else 0,
                    "staging_folder": staging_folder,
                    "staging_folder_file_type": file_type,
                    "file_count": file_count,
                    "group": preprocess_cfg['group'],
                    "pid": pid,
                    "status": pid_status,
                    "not_running_starttime": not_running_timestamp
                })
        self.data_list = data_list
        self.save_status_to_json()  # Save to JSON after building the initial list
        return data_list

    def run_perl_script(self, script_path, config_file, status_flag, mode, selection):
        if not os.path.isfile(script_path):
            raise FileNotFoundError(f"Script path does not exist: {script_path}")
        
        def execute_command(command, mode, selection):
            """ Helper function to execute a command with subprocess """
            Log.INFO(f"Executing command: {command}")
            command_parts = shlex.split(command)
            with subprocess.Popen(command_parts, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
                process.stdin.write(f'{mode}\n{selection}\n'.encode())
                process.stdin.flush()
                stdout, stderr = process.communicate()
                if stderr:
                    Log.ERROR(f"Errors occurred: {stderr.decode()}")
                    return None, "error"
                return stdout.decode().strip().split('\n')[-1], process.returncode

        # Kill the process to clean/remove pid file
        kill_cmd = f'{script_path} -f {config_file} -kill'
        kill_output, kill_status = execute_command(kill_cmd, mode, selection)
        Log.INFO(kill_output)
        time.sleep(30)  # Wait for the process to fully terminate

        # Start the process
        start_cmd = f'{script_path} -f {config_file} {status_flag}'
        start_output, start_status = execute_command(start_cmd, mode, selection)
        Log.INFO(start_output)
        time.sleep(30)  # Allow some time for the process to initialize

        # Evaluate the result based on the subprocess return code
        if start_status is None:
            Log.INFO("The Perl script is still running.")
            return "test"
        elif start_status == 0:
            Log.INFO("The Perl script finished successfully.")
            return "started"
        else:
            Log.ERROR(f"The Perl script exited with status {start_status}.")
            return "error"

    # def is_log_file_active(self, log_file_path, interval=0):
    #     return Util.is_log_file_active(log_file_path, interval)

    def monitor_processes(self):
        while True:
            temp_data_list = []
            for data in self.data_list:
                script_path = self.yaml_data['dp_load_mgr']
                mgr_file = self.yaml_data['mgr_file']
                cfg_file = data['cfg_file']
                dp_status_flag = "-start"
                mode = "2"
                seq_num = data['sequence']
                log_file = data['log_file']
                staging_folder = data['staging_folder']
                file_type = data['staging_folder_file_type']
                pid = data['pid']
                status = data['status']
                cfg_sleep_time = data['sleep_time']
                log_file_exists = log_file and os.path.isfile(log_file)
                staging_folder_file_count = Util.count_files_in_folder(staging_folder, file_type)

                # Initialize not_running_starttime if not set and log file is inactive
                if staging_folder_file_count > 0 and pid and status == 'Running' and log_file_exists:
                    if not Util.is_logfile_active(log_file, 5):
                        if data['not_running_starttime'] is None:
                            data['not_running_starttime'] = Util.get_current_timestamp()
                            data['initial_staging_count'] = staging_folder_file_count
                            Log.INFO(f"Monitoring started for inactivity in log file: {log_file}")

                # Check if 5 minutes have passed and the file count has not decreased
                if data['not_running_starttime'] is not None:
                    if Util.has_five_minutes_passed(data['not_running_starttime']):
                        current_staging_folder_file_count = Util.count_files_in_folder(staging_folder, file_type)
                        if current_staging_folder_file_count >= data['initial_staging_count']:
                            Log.INFO(f"5 minutes of inactivity detected. No decrease in files for PID {pid} in staging folder. Attempting to restart process.")
                            Log.INFO(f"Restarting cfg sequence number={seq_num} || cfg group={data['group']}")
                            # Attempt to restart the process
                            restart_result = self.run_perl_script(script_path, mgr_file, dp_status_flag, mode, seq_num)
                            if restart_result == "started":
                                Log.INFO("Process restarted successfully.")
                                data['status'] = "Running"
                                data['not_running_starttime'] = None  # Reset the timer
                            else:
                                Log.ERROR("Failed to restart process.")
                                data['status'] = "Not Running"
                
                temp_data_list.append(data)
            self.data_list = temp_data_list
            self.save_status_to_json()
            time.sleep(self.sleep_time)

    def save_status_to_json(self):
        with self.status_lock:
            with open(STATUS_FILE, 'w') as file:
                json.dump(self.data_list, file, indent=4)

# Start monitoring in a background thread
def start_monitoring():
    monitor = Monitor(YAML_FILE)
    monitoring_thread = threading.Thread(target=monitor.monitor_processes, daemon=True)
    monitoring_thread.start()
    return monitor

if __name__ == '__main__':
    start_monitoring()
    while True:
        time.sleep(3)
