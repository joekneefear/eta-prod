import os
import time
import glob
import subprocess
import threading
import sys
import uvicorn
import asyncio
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional

# from lib.Util import Util
# from lib.Log import Log
# Import Log and Util classes from the lib module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from lib import Log, Util



# Environment Configuration
log_file = os.getenv('LOG_FILE', '/export/home/dpower/project/log/fcs_preprocessor_monitor.log')
yaml_file = os.getenv('YAML_FILE', '/export/home/dpower/jag/eta_master/scripts/py/monitor/preprocessor_monitor.yml')
status_file = os.getenv('STATUS_FILE', '/export/home/dpower/jag/eta_master/scripts/py/monitor/status.json')
# Configure logging
Log.configure_logger(log_file)
logger = Log.get_logger()

class Monitor:
    def __init__(self, yaml_file):
        self.yaml_data = Util.load_yaml(yaml_file)
        self.data_list = self.yaml_data.get('processes', [])
        self.not_running_start_time = {}
        self.restart_threshold = self.yaml_data.get('restart_threshold_seconds', 300)
        self.sleep_time = self.yaml_data.get('sleep_time_seconds', 60)

    def run_perl_script(self, script_path, config_file, status_flag, mode, selection):
        command = f"perl {script_path} {config_file} {status_flag} {mode} {selection}"
        logger.info(f'Running command: {command}')
        subprocess.run(command, shell=True)

    def get_file_type(self, file_path):
        mime = magic.Magic()
        file_type = mime.from_file(file_path)
        return file_type.split('/')[-1]

    def monitor_processes(self):
        for data in self.data_list:
            seq_num = data['sequence']
            config_file = data['cfg_file']
            log_file_path = data['log_file']
            script_path = self.yaml_data['dp_load_mgr']
            dp_status_flag = "-start"
            mode = "2"
            staging_folder = data['staging_folder']
            file_type = data['staging_folder_file_type']
            pid = data['pid']
            files = []

            log_file_exists = os.path.isfile(log_file_path)
            log_file_inactive = not os.path.getsize(log_file_path) if log_file_exists else True
            if log_file_exists and os.path.getsize(log_file_path) > 0:
                log_file_inactive = (time.time() - os.path.getmtime(log_file_path)) > self.restart_threshold

            files = [f for f in glob.glob(os.path.join(staging_folder, '*')) if os.path.isfile(f)]
            if files:
                if file_type != '%' and file_type.lower() == 'na':
                    file_type = self.get_file_type(files[0])
                    files = [f for f in glob.glob(os.path.join(staging_folder, '*')) if os.path.isfile(f) and os.path.splitext(f)[1][1:].lower() == file_type.lower()]
                if file_type != '%' and file_type.lower() != 'na':
                    files = [f for f in glob.glob(os.path.join(staging_folder, '*')) if os.path.isfile(f) and os.path.splitext(f)[1][1:].lower() == file_type.lower()]
            files_present = len(files) > 0
            data['file_count'] = len(files)
            pid_active = pid and os.path.exists(f'/proc/{pid}')
            if data['status'] == 'NOT RUNNING' and seq_num in self.not_running_start_time:
                elapsed_time = time.time() - self.not_running_start_time[seq_num]
                # if elapsed_time > self.restart_threshold:
                #     logger.info(f'Elapsed time={elapsed_time} is greater than threshold={self.restart_threshold}')
                #     self.run_perl_script(script_path, config_file, dp_status_flag, mode, seq_num)
            elif data['status'] == 'RUNNING' and seq_num in self.not_running_start_time:
                del self.not_running_start_time[seq_num]
            if pid_active:
                data['status'] = "RUNNING"
            if log_file_exists and not log_file_inactive and pid_active:
                data['status'] = 'RUNNING'
            elif log_file_inactive and files_present and pid_active:
                self.not_running_start_time[seq_num] = time.time()
                data['status'] = 'NOT RUNNING'
            elif log_file_inactive and not files_present and pid_active:
                data['status'] = 'RUNNING'

    def get_status(self):
        return self.data_list

    def monitor_every_x_seconds(self):
        while True:
            self.monitor_processes()
            time.sleep(self.sleep_time)

# FastAPI setup
app = FastAPI()

# Add CORS middleware
origins = os.getenv('CORS_ORIGINS', "http://localhost:3000,http://localhost:5173,http://localhost:5174").split(',')

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class MonitorData(BaseModel):
    sequence: Optional[int] = None
    cfg_file: Optional[str] = None
    log_file: Optional[str] = None
    sleep_time: Optional[int] = None
    staging_folder: Optional[str] = None
    staging_folder_file_type: Optional[str] = None
    file_count: Optional[int] = None
    group: Optional[str] = None
    pid: Optional[str] = None
    status: Optional[str] = None

# Dependency
def get_monitor():
    return Monitor(yaml_file)

@app.post("/start_process/{sequence}")
async def start_process(sequence: int):
    process = next((p for p in monitor.data_list if p['sequence'] == sequence), None)
    if process and process['status'] == 'NOT RUNNING':
        script_path = monitor.yaml_data['dp_load_mgr']
        config_file = monitor.yaml_data['mgr_file']
        status_flag = "-start"
        mode = "2"
        selection = str(process['sequence'])
        monitor.run_perl_script(script_path, config_file, status_flag, mode, selection)
        return {"message": "Process started successfully"}
    else:
        raise HTTPException(status_code=400, detail="Process not found or already running")

@app.get("/status", response_model=List[MonitorData])
async def get_status(monitor=Depends(get_monitor)):
    return monitor.get_status()

if __name__ == "__main__":
    monitor_thread = threading.Thread(target=Monitor(yaml_file).monitor_every_x_seconds, daemon=True)
    monitor_thread.start()
    try:
        loop = asyncio.get_event_loop()
        server = uvicorn.Server(uvicorn.Config("test:app", host="0.0.0.0", port=5500, log_level="info"))
        loop.run_until_complete(server.serve())
        loop.run_forever()
    except KeyboardInterrupt:
        logger.info('Shutting down...')
        monitor_thread.join()
        logger.info("Thread terminated.")
    finally:
        loop.close()

# @app.get("/status", response_model=List[MonitorData])
# async def get_status():
#     return monitor.get_status()

# if __name__ == "__main__":
#     monitor = Monitor(yaml_file)
#     monitor_thread = threading.Thread(target=monitor.monitor_every_x_seconds, daemon=True)
#     monitor_thread.start()
#     try:
#         loop = asyncio.get_event_loop()
#         server = uvicorn.Server(uvicorn.Config("test:app", host="0.0.0.0", port=5500, log_level="info"))
#         loop.run_until_complete(server.serve())
#         loop.run_forever()
#     except KeyboardInterrupt:
#         logger.info('Shutting down...')
#         monitor_thread.join()
#         logger.info("Thread terminated.")
#     finally:
#         loop.close()

# # Main entry point
# if __name__ == "__main__":
#     monitor = Monitor(yaml_file)
#     monitor_thread = threading.Thread(target=monitor.monitor_every_x_seconds, daemon=True)
#     monitor_thread.start()
#     try:
#         uvicorn.run("test:app", host="0.0.0.0", port=5500)
#     except KeyboardInterrupt:
#         logger.info('Shutting down...')
#         monitor_thread.join()
#         logger.info("Thread terminated.")
