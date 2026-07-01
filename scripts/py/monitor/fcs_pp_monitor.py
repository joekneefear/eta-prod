import os
import time
import shlex
import subprocess
import threading
import json
import asyncio
import sys

# Import Log and Util classes from the lib module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from lib import Log, Util

# Environment Configuration
log_file = os.getenv('LOG_FILE', '/export/home/dpower/project/log/fcs_preprocessor_monitor.log')
yaml_file = os.getenv('YAML_FILE', '/export/home/dpower/jag/eta_master/scripts/py/monitor/preprocessor_monitor.yml')
status_file = os.getenv('STATUS_FILE', '/export/home/dpower/jag/eta_master/scripts/py/monitor/status.json')

# Configure logging
Log.configure_logger(log_file=log_file)
logger = Log.get_logger()

# Custom asyncio.run for Python 3.6
def asyncio_run(coroutine):
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    result = loop.run_until_complete(coroutine)
    loop.close()
    return result

# Monitor class
class Monitor:
    _instance = None

    def __new__(cls, yaml_file):
        if cls._instance is None:
            cls._instance = super(Monitor, cls).__new__(cls)
            cls._instance._initialize(yaml_file)
        return cls._instance

    def _initialize(self, yaml_file):
        self.not_running_start_time = {}
        self.yaml_data = Util.load_yaml(yaml_file)
        self.restart_threshold = self.yaml_data['auto_restart_threshold']
        self.sleep_time = self.yaml_data['monitor_sleep_time']
        self.data_list = self.build_preprocessing_info()
        self.status_lock = threading.RLock()

    def parse_mgr_file(self, file_path):
        if not os.path.isfile(file_path):
            raise ValueError("{} does not exist.".format(file_path))
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
                    raise ValueError("Line {} is not formatted correctly.".format(sequence))
                parsed_list.append(line_dict)
                sequence += 1
        return parsed_list

    def parse_cfg_file(self, cfg_file):
        try:
            with open(cfg_file, 'r') as file:
                for line in file:
                    if line.startswith('#') or '#' in line:
                        continue
                    columns = line.split(':')
                    staging_folder = columns[0].strip() if len(columns) > 0 else None
                    if staging_folder and staging_folder not in ['NA', 'N/A']:
                        if staging_folder.startswith('$DPDATA'):
                            staging_folder = staging_folder.replace('$DPDATA', self.yaml_data['DPDATA'])
                        if staging_folder.startswith('$REFERENCE_DATA_DIR'):
                            staging_folder = staging_folder.replace('$REFERENCE_DATA_DIR', self.yaml_data['REFERENCE_DATA_DIR'])
                    file_type = columns[2].strip() if len(columns) > 2 else None
                    logfile_value = self.get_value_after_string(columns[3], ["log", "log_file", "logfile"]) if len(columns) > 2 else None
                    if logfile_value and logfile_value.startswith('$DPLOG'):
                        logfile_value = logfile_value.replace('$DPLOG', self.yaml_data['DPLOG'])
                    if logfile_value and logfile_value.startswith('$DPDATA'):
                        logfile_value = logfile_value.replace('$DPDATA', self.yaml_data['DPDATA'])
                    source_folder = self.get_value_after_string(columns[3], ["source", "inbox"]) if len(columns) > 2 else None
                    if source_folder and source_folder.startswith('$DPDATA'):
                        source_folder = source_folder.replace('$DPDATA', self.yaml_data['DPDATA'])
                    if not staging_folder or staging_folder in ['NA', 'N/A'] and source_folder:
                        staging_folder = source_folder
                    return staging_folder, file_type, logfile_value
        except FileNotFoundError:
            Log.INFO("File {} not found.".format(cfg_file))
            return None, None, None

    def get_value_after_string(self, s, targets):
        s = s.replace('=', ' ')
        parts = s.split()
        for i, part in enumerate(parts):
            if any(target in part for target in targets) and i + 1 < len(parts):
                return parts[i + 1]
        return None

    def get_file_type(self, filename):
        known_compressed_types = ['gz', 'zip']
        parts = filename.split('.')
        if len(parts) > 2 and parts[-1] in known_compressed_types:
            file_type = parts[-2]
        else:
            file_type = parts[-1] if len(parts) > 1 else None
        return file_type

    def build_preprocessing_info(self):
        mgr_file = self.yaml_data['mgr_file']
        data_list = []
        mgr_data_lines = self.parse_mgr_file(mgr_file)
        for preprocess_cfg in mgr_data_lines:
            cfg_file = preprocess_cfg['cfg']
            if cfg_file:
                cfg_file = cfg_file.replace('$DPLOAD', self.yaml_data['DPLOAD'])
            staging_folder, file_type, logfile = self.parse_cfg_file(cfg_file)
            if staging_folder is None and file_type is None and logfile is None:
                continue
            pid_file = cfg_file + '.pid'
            pid = None
            try:
                with open(pid_file, 'r') as f:
                    pid = f.readline().strip()
            except FileNotFoundError:
                pass
            
            data_list.append({
                "sequence": preprocess_cfg['sequence'],
                "cfg_file": cfg_file,
                "log_file": logfile,
                "sleep_time": int(preprocess_cfg['sleep']) if preprocess_cfg['sleep'] else None,
                "staging_folder": staging_folder,
                "staging_folder_file_type": file_type,
                "file_count": 0,
                "group": preprocess_cfg['group'],
                "pid": pid,
                "status": ""
            })
        return data_list

    def run_perl_script(self, script_path, config_file, status_flag, mode, selection):
        if not os.path.isfile(script_path):
            raise ValueError("{} does not exist.".format(script_path))
        stderr = None  # Initialize stderr
        try:
            start_cmd = '{0} -f {1} {2}'.format(script_path, config_file, status_flag)
            kill_cmd = '{0} -f {1} -kill'.format(script_path, config_file)
            Log.INFO('kill the preprocess first to clean/remove pid file')
            kill_cmd_parts = shlex.split(kill_cmd)
            process = subprocess.Popen(kill_cmd_parts, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            process.stdin.write('{0}\n{1}\n'.format(mode, selection).encode())
            process.stdin.flush()
            stdout, stderr = process.communicate()
            output = stdout.decode()
            lines = output.split('\n')
            for line in lines:
                if line:
                    Log.INFO('KILL preprocess command output={}'.format(line))
            
            Log.INFO('start the preprocess after kill')
            start_cmd_parts = shlex.split(start_cmd)
            process = subprocess.Popen(start_cmd_parts, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            process.stdin.write('{0}\n{1}\n'.format(mode, selection).encode())
            process.stdin.flush()
            stdout, stderr = process.communicate()
            output = stdout.decode()
            lines = output.split('\n')
            for line in lines:
                if line:
                    Log.INFO(line)
            if process.returncode is None:
                Log.INFO("The Perl script is still running.")
            elif process.returncode == 0:
                Log.INFO("The Perl script finished successfully.")
            else:
                Log.ERROR("The Perl script exited with status {}.".format(process.returncode))
        except Exception as e:
            Log.ERROR("Error running Perl script: {}".format(str(e)))
        finally:
            if stderr:
                Log.ERROR(stderr.decode())

    async def is_log_file_active_async(self, log_file, timeout):
        timeout = 3600  # 1 hour
        now = time.time()
        while time.time() - now < timeout:
            if os.path.isfile(log_file):
                return True
            await asyncio.sleep(10)
        return False

    def get_status(self):
        with self.status_lock:
            try:
                with open(status_file, 'r') as f:
                    return json.load(f)
            except FileNotFoundError:
                return {}

    def update_status(self):
        with self.status_lock:
            try:
                with open(status_file, 'w') as f:
                    json.dump(self.data_list, f, indent=4)
            except FileNotFoundError:
                raise HTTPException(status_code=404, detail="Status file not found.")

    def update_monitor_status(self, status):
        with self.status_lock:
            try:
                with open(status_file, 'r') as f:
                    data_list = json.load(f)
            except FileNotFoundError:
                raise FileNotFoundError("Status file not found.")
            for item in data_list:
                if item["sequence"] == status["sequence"]:
                    item["status"] = status["status"]
                    break
            with open(status_file, 'w') as f:
                json.dump(data_list, f, indent=4)

    def check_and_restart_preprocess(self):
        for data in self.data_list:
            if not data.get('pid'):
                continue
            pid = data['pid']
            try:
                os.kill(int(pid), 0)
            except OSError:
                log_path = data['log_file']
                if log_path and not os.path.exists(log_path):
                    self.run_perl_script(self.yaml_data['perl_script_path'], data['cfg_file'], data['group'], "start", "mode")

    def monitor_preprocessors(self):
        while True:
            for data in self.data_list:
                pid = data.get("pid")
                log_file = data.get("log_file")
                if pid:
                    try:
                        os.kill(int(pid), 0)
                        logger.info("Process with PID {} is running.".format(pid))
                        if log_file:
                            logger.info("Log file path is {}.".format(log_file))
                            asyncio_run(self.is_log_file_active_async(log_file, 3600))
                    except OSError:
                        logger.info("Process with PID {} is not running.".format(pid))
                        self.not_running_start_time[pid] = time.time()
                        if log_file:
                            asyncio_run(self.is_log_file_active_async(log_file, 0))
            self.update_status()
            time.sleep(self.sleep_time)

    def main(self):
        while True:
            for data in self.data_list:
                pid = data.get("pid")
                log_file = data.get("log_file")
                if pid:
                    try:
                        os.kill(int(pid), 0)
                        logger.info("Process with PID {} is running.".format(pid))
                        if log_file:
                            logger.info("Log file path is {}.".format(log_file))
                            asyncio_run(self.is_log_file_active_async(log_file, 3600))
                    except OSError:
                        logger.info("Process with PID {} is not running.".format(pid))
                        self.not_running_start_time[pid] = time.time()
                        if log_file:
                            asyncio_run(self.is_log_file_active_async(log_file, 0))
            self.update_status()
            time.sleep(self.sleep_time)

if __name__ == "__main__":
    monitor_instance = Monitor(yaml_file)
    monitor_thread = threading.Thread(target=monitor_instance.main, daemon=True)
    monitor_thread.start()
    monitor_thread.join()
