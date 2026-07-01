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
import re
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Import Log and Util classes from the lib module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from lib import Log, Util

# Environment Configuration
LOG_FILE = os.getenv('LOG_FILE', '/export/home/dpower/project/log/fcs_preprocessor_monitor.log')
YAML_FILE = os.getenv('YAML_FILE', '/export/home/dpower/jag/eta_master/scripts/py/monitor/preprocessor_monitor.yml')
STATUS_FILE = os.getenv('STATUS_FILE', '/export/home/dpower/jag/eta_master/scripts/py/monitor/status.json')
EMAIL_RECIPIENTS = os.getenv('EMAIL_RECIPIENTS', 'junifferallan.garcia@onsemi.com').split(',')
smtp_server = "mailhost.onsemi.com"

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
        self.status_lock = threading.RLock()
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

                        parts = re.split(r'[:\s]', line)
                        staging_folder = parts[0] if parts else None
                        file_type = parts[2] if len(parts) > 1 else None
                        logfile_value = self.get_value_after_string(line, ["--log", "-log", "--logfile", "-logfile", "--log_file", "-log_file"])
                        source_folder = self.get_value_after_string(line, ["--inbox", "-inbox", "--source", "-source"])

                        staging_folder = self.resolve_variable(staging_folder) if staging_folder else None
                        logfile_value = self.resolve_variable(logfile_value) if logfile_value else None
                        source_folder = self.resolve_variable(source_folder) if source_folder else None

                        if not staging_folder or staging_folder.lower() in ['na', 'n/a', '']:
                            if source_folder:
                                staging_folder = source_folder
                            else:
                                Log.ERROR(f'No staging folder found, pls check the cfg file {cfg_file}')
                                Util.dp_exit(1, f"No staging folder found, could be cfg file is malformed {cfg_file}")

                        return staging_folder, file_type, logfile_value
            except FileNotFoundError:
                Log.INFO(f"CFG File {cfg_file}")
                Util.dp_exit(1, f"ERROR malformed cfg file={cfg_file}")
        else:
            Log.INFO(f'cfg file did not exist={cfg_file}')
            Util.dp_exit(1, 'cfg not found')

    def resolve_variable(self, path):
        variable_mapping = {
            '$DPDATA': self.yaml_data['DPDATA'],
            '$REFERENCE_DATA_DIR': self.yaml_data['REFERENCE_DATA_DIR'],
            '$DPLOG': self.yaml_data['DPLOG']
        }
        for variable, value in variable_mapping.items():
            if path.startswith(variable):
                return path.replace(variable, value)
        return path

    def get_value_after_string(self, s, targets):
        parts = re.split(r'[\s=]', s)
        for i, part in enumerate(parts):
            if part in targets and i + 1 < len(parts):
                return parts[i + 1]
        return None

    def build_preprocessing_info(self):
        mgr_file = self.yaml_data['mgr_file']
        data_list = []
        mgr_data_lines = self.parse_mgr_file(mgr_file)
        for preprocess_cfg in mgr_data_lines:
            cfg_file = preprocess_cfg['cfg']
            if cfg_file:
                cfg_file = cfg_file.replace('$DPLOAD', self.yaml_data['DPLOAD'])
                staging_folder, file_type, logfile = self.parse_cfg_file(cfg_file)
                file_count = Util.count_files_in_folder(staging_folder, file_type)
                pid_file = cfg_file + '.pid'
                pid = Util.get_pid_from_file(pid_file) if Util.check_file_exists(pid_file) else None
                if pid and Util.is_pid_running(pid):
                    pid_status = "Running"
                    not_running_timestamp = None
                else:
                    pid_status = "Not Running"
                    not_running_timestamp = Util.get_current_timestamp()
                    Log.INFO(f'Please check has pid file but no PID..' if pid else f'PID file = {pid_file} not found')

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
        self.save_status_to_json()
        return data_list

    def run_perl_script(self, script_path, config_file, status_flag, mode, selection):
        if not os.path.isfile(script_path):
            raise ValueError(f"{script_path} does not exist.")
        try:
            start_cmd = f'{script_path} -f {config_file} {status_flag}'
            kill_cmd = f'{script_path} -f {config_file} -kill'
            Log.INFO(f'kill the preprocess first to clean/remove pid file')
            self.execute_command(kill_cmd, mode, selection)
            time.sleep(30)
            Log.INFO(f'start the preprocess after kill')
            result = self.execute_command(start_cmd, mode, selection)
            time.sleep(30)
            return result
        except Exception as e:
            Log.ERROR(f"An error occurred: {str(e)}")
            return "error"

    def execute_command(self, command, mode, selection):
        process = subprocess.Popen(shlex.split(command), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        process.stdin.write(f'{mode}\n{selection}\n'.encode())
        process.stdin.flush()
        stdout, stderr = process.communicate()
        output = stdout.decode()
        Log.INFO(output.split('\n')[-1])
        if process.returncode is None:
            Log.INFO("The Perl script is still running.")
            return "test"
        elif process.returncode == 0:
            Log.INFO("The Perl script finished successfully.")
            return "started"
        else:
            Log.ERROR(f"The Perl script exited with status {process.returncode}.")
            return "error"

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

                if staging_folder_file_count > 0 and pid and status == 'Running' and log_file_exists:
                    if not Util.is_logfile_active(log_file, 5):
                        if data['not_running_starttime'] is None:
                            data['not_running_starttime'] = Util.get_current_timestamp()
                            data['initial_staging_count'] = staging_folder_file_count  # Ensure this key is set
                            Log.INFO(f"Monitoring started for inactivity in log file: {log_file}")

                if data['not_running_starttime'] is not None:
                    if Util.has_five_minutes_passed(data['not_running_starttime']):
                        current_staging_folder_file_count = Util.count_files_in_folder(staging_folder, file_type)
                        if 'initial_staging_count' not in data:
                            data['initial_staging_count'] = current_staging_folder_file_count

                        if current_staging_folder_file_count >= data['initial_staging_count']:
                            Log.INFO(f"5 minutes of inactivity detected. No decrease in files for PID {pid} in staging folder. Attempting to restart process.")
                            Log.INFO(f"Restarting cfg sequence number={seq_num} || cfg group={data['group']}")
                            restart_result = self.run_perl_script(script_path, mgr_file, dp_status_flag, mode, seq_num)
                            if restart_result == "started":
                                Log.INFO("Process restarted successfully.")
                                data['status'] = "Running"
                                data['not_running_starttime'] = None
                                self.send_email_notification(seq_num, data['group'], "success")
                            else:
                                Log.ERROR("Failed to restart process.")
                                data['status'] = "Not Running"
                                self.send_email_notification(seq_num, data['group'], "failure")
                        else:
                            self.send_email_notification(seq_num, data['group'], "not_running")
                
                temp_data_list.append(data)
            self.data_list = temp_data_list
            self.save_status_to_json()
            time.sleep(self.sleep_time)

    def generate_html_report(self, title, table_headers, table_data):
        html_content = f"""
        <html>
        <head>
        <meta http-equiv="Content-Type" content="text/html; charset=us-ascii">
        <style>
        body {{
          font-family: Arial, sans-serif;
          border: 1px solid #ddd;
        }}
        .report {{
          border: 1px solid #2299ee; 
          padding: 20px;
          max-width: 800px;
          margin: 0 auto;
        }}
        h1 {{
          text-align: center; 
          color: #808080;
        }}
        table {{
          width: 100%;
          border-collapse: collapse; 
        }}
        th {{
          background-color: #FFA500;
          color: white;
          padding: 10px; 
          text-align: left;
        }}
        td {{ 
          border: 1px solid #eee;
          padding: 10px;
        }}
        .size {{
          font-weight: bold;
        }}
        .size_red {{
          color: white;
          font-weight: bold !important;
          background-color: #FF0000;
        }}
        </style>
        </head>
        <body>
        <div class="report">
        <h1>{title}</h1> 
        <table>
        <tr>
        """
        for header in table_headers:
            html_content += f"<th>{header}</th>"
        html_content += "</tr>"
        
        for row in table_data:
            html_content += "<tr>"
            for cell in row:
                html_content += f"<td>{cell}</td>"
            html_content += "</tr>"
        
        html_content += """
        </table>
        </div>
        </body>
        </html>
        """
        return html_content

    def send_email_notification(self, sequence, group, status):
        subject = "Process Status Notification"
        if status == "not_running":
            body = f"""
            <html>
            <head>
            <meta http-equiv="Content-Type" content="text/html; charset=us-ascii">
            <style>
            body {{
              font-family: Arial, sans-serif;
              border: 1px solid #ddd;
            }}
            .report {{
              border: 1px solid #2299ee; 
              padding: 20px;
              max-width: 800px;
              margin: 0 auto;
            }}
            h1 {{
              text-align: center; 
              color: #808080;
            }}
            table {{
              width: 100%;
              border-collapse: collapse; 
            }}
            th {{
              background-color: #FFA500;
              color: white;
              padding: 10px; 
              text-align: left;
            }}
            td {{ 
              border: 1px solid #eee;
              padding: 10px;
            }}
            .size {{
              font-weight: bold;
            }}
            .size_red {{
              color: white;
              font-weight: bold !important;
              background-color: #FF0000;
            }}
            </style>
            </head>
            <body>
            <div class="report">
            <h1>Process Status Notification</h1> 
            <table>
              <tr>
                <th>Sequence</th>  
                <th>Group</th>
                <th>Status</th>
              </tr>
              <tr>
                <td>{sequence}</td>
                <td>{group}</td> 
                <td class="size_red">Not Running</td>
              </tr>
            </table>
            </div>
            </body>
            </html>
            """
        elif status == "success":
            body = f"""
            <html>
            <head>
            <meta http-equiv="Content-Type" content="text/html; charset=us-ascii">
            <style>
            body {{
              font-family: Arial, sans-serif;
              border: 1px solid #ddd;
            }}
            .report {{
              border: 1px solid #2299ee; 
              padding: 20px;
              max-width: 800px;
              margin: 0 auto;
            }}
            h1 {{
              text-align: center; 
              color: #808080;
            }}
            table {{
              width: 100%;
              border-collapse: collapse; 
            }}
            th {{
              background-color: #FFA500;
              color: white;
              padding: 10px; 
              text-align: left;
            }}
            td {{ 
              border: 1px solid #eee;
              padding: 10px;
            }}
            .size {{
              font-weight: bold;
            }}
            .size_red {{
              color: white;
              font-weight: bold !important;
              background-color: #FF0000;
            }}
            </style>
            </head>
            <body>
            <div class="report">
            <h1>Process Status Notification</h1> 
            <table>
              <tr>
                <th>Sequence</th>  
                <th>Group</th>
                <th>Status</th>
              </tr>
              <tr>
                <td>{sequence}</td>
                <td>{group}</td> 
                <td class="size">Restarted Successfully</td>
              </tr>
            </table>
            </div>
            </body>
            </html>
            """
        else:
            body = f"""
            <html>
            <head>
            <meta http-equiv="Content-Type" content="text/html; charset=us-ascii">
            <style>
            body {{
              font-family: Arial, sans-serif;
              border: 1px solid #ddd;
            }}
            .report {{
              border: 1px solid #2299ee; 
              padding: 20px;
              max-width: 800px;
              margin: 0 auto;
            }}
            h1 {{
              text-align: center; 
              color: #808080;
            }}
            table {{
              width: 100%;
              border-collapse: collapse; 
            }}
            th {{
              background-color: #FFA500;
              color: white;
              padding: 10px; 
              text-align: left;
            }}
            td {{ 
              border: 1px solid #eee;
              padding: 10px;
            }}
            .size {{
              font-weight: bold;
            }}
            .size_red {{
              color: white;
              font-weight: bold !important;
              background-color: #FF0000;
            }}
            </style>
            </head>
            <body>
            <div class="report">
            <h1>Process Status Notification</h1> 
            <table>
              <tr>
                <th>Sequence</th>  
                <th>Group</th>
                <th>Status</th>
              </tr>
              <tr>
                <td>{sequence}</td>
                <td>{group}</td> 
                <td class="size_red">Failed to Restart</td>
              </tr>
            </table>
            </div>
            </body>
            </html>
            """
        
        msg = MIMEMultipart()
        msg['From'] = 'yms.admins@onsemi.com'
        msg['To'] = ', '.join(EMAIL_RECIPIENTS)
        msg['Subject'] = subject
        msg.attach(MIMEText(body, 'html'))
        try:
            with smtplib.SMTP(smtp_server) as server:
                server.sendmail(msg['From'], EMAIL_RECIPIENTS, msg.as_string())
            Log.INFO("Email notification sent successfully.")
        except Exception as e:
            Log.ERROR(f"Failed to send email notification: {str(e)}")

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
