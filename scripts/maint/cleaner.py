#!/usr/bin/env python3
"""
This script is designed to process files and folders based on specified conditions.
It allows you to set a root directory and a target folder, and it will process all files
and folders within the root directory that match the target folder name, up to a specified
maximum depth. Files that are older than a specified age threshold will be deleted (or just
listed in test mode).

The script includes the following features:
- Argument parsing for specifying root directory, target folder, age threshold, test mode, log file path, profiling option, and monitoring option
- Logging functionality using a custom Log module
- File and folder processing using custom FileProcessor and FolderProcessor classes
- Signal handling for SIGINT (Ctrl+C) to gracefully terminate the script
- Locking mechanism to prevent multiple instances of the script from running simultaneously for the same root directory and target folder combination
- System resource monitoring in a separate thread (optional)
- Profiling option to analyze the script's performance
- Error handling and cleanup mechanisms

The script is designed to be run from the command line and requires Python 3.x to run.
"""

import sys
import os
import time
import threading
import psutil
import signal
import cProfile
import argparse
from pathlib import Path
sys.path.insert(0, '/export/home/dpower/project/scripts/py/lib')
from Log import Log
from processing.folder_processor import FolderProcessor
from processing.file_processor import FileProcessor
import globals
from utils.file_utils import monitor_system, cleanup, signal_handler

lock_file = None
pid_file = None

# Argument parsing
parser = argparse.ArgumentParser()
parser.add_argument("-d", "--root-dir", required=True, help="Path to the root directory to process.")
parser.add_argument("-t", "--target-folder", required=True, help="Name of the target folder to process.")
parser.add_argument("-a", "--age-threshold", type=int, default=30, help="Age threshold in days for files to be deleted.")
parser.add_argument("--test", action="store_true", help="Run in test mode. Files will not be deleted.")
parser.add_argument("-l", "--logfile", default='maxdepth_folder_file_cleaner.log', help="Path to the log file.")
parser.add_argument("--profile", action="store_true", help="Enable profiling.")
parser.add_argument("--monitor", action="store_true", help="Enable system resource monitoring.")
args = parser.parse_args()

def main():
    """
    Main function that serves as the entry point for the script.
    It performs the following tasks:
    1. Declares lock_file and pid_file as global variables
    2. Sets up signal handler for SIGINT (Ctrl+C)
    3. Validates the root directory
    4. Creates a unique lock file and PID file
    5. Instantiates FileProcessor and FolderProcessor objects
    6. Processes the root directory based on specific conditions
    7. Handles exceptions and performs cleanup operations
    8. Disables profiling and prints profiling statistics, if enabled
    """
    global lock_file, pid_file  # Declare them as global inside the function
    # Signal handler for termination signals
    signal.signal(signal.SIGINT, signal_handler(lock_file, pid_file))

    root_dir = args.root_dir
    target_folder = args.target_folder
    age_threshold_days = args.age_threshold
    test_mode = args.test
    log_file = args.logfile
    profile = args.profile
    Log.configure_logger(log_file=log_file)
    logger = Log.get_logger()

    # Validate root directory
    if not os.path.exists(root_dir) or not os.path.isdir(root_dir):
        raise ValueError("Invalid root directory provided.")

    # Create a unique lock file for each root_dir and target_folder
    root_dir_name = root_dir.replace('/', '_')
    script_dir = os.path.dirname(os.path.realpath(__file__))
    lock_file = f"{script_dir}/{root_dir_name}_{target_folder}.lock"

    if os.path.exists(lock_file):
        print(f"Another instance of the script is already running for root_dir {root_dir} and target_folder {target_folder}")
        sys.exit(1)

    # Create the lock file
    open(lock_file, 'a').close()

    # Write the PID to a file
    pid_file = f"{script_dir}/{root_dir_name}.pid"
    with open(pid_file, 'w') as f:
        f.write(str(os.getpid()))

    file_processor = FileProcessor(age_threshold_days, test_mode, lock_file, pid_file)
    folder_processor = FolderProcessor(root_dir, target_folder, file_processor, lock_file, pid_file)

    # Process the root directory
    try:
        # Check if the root directory is the target folder and contains only files
        root_entries = list(os.scandir(folder_processor.root_dir))
        if folder_processor.root_dir.name == folder_processor.target_folder and all((entry.is_file() or (entry.is_dir() and entry.name != folder_processor.target_folder)) for entry in root_entries):
            # Process each file directly
            files = [entry.path for entry in root_entries if entry.is_file() and not entry.name.startswith('.')]
            for file in files:
                folder_processor.file_processor.process_file_entry(Path(file))
        else:
            # Call process_folder
            folder_processor.find_process_max_depth_folders_files()
    except Exception as e:
        Log.ERROR("An error occurred during folder processing: %s" % str(e))
        globals.script_terminating = True  # Set the flag to stop monitoring thread
        if globals.script_terminating:
            # Read the PID from the file
            with open(pid_file, 'r') as f:
                pid = int(f.read())
            # Check if the process is still running
            if psutil.pid_exists(pid):
                # Send a SIGTERM signal to the process
                os.kill(pid, signal.SIGTERM)
        cleanup(lock_file, pid_file)
        sys.exit(1)  # Terminate the script immediately
    finally:
        globals.script_terminating = True  # Set the flag to stop monitoring thread
        cleanup(lock_file, pid_file)
        if args.profile:
            profiler = cProfile.Profile()
            profiler.enable()
            profiler.disable()
            profiler.print_stats()

if __name__ == "__main__":
    try:
        if args.monitor:
            # Start monitoring system resources in a separate thread
            monitor_thread = threading.Thread(target=monitor_system, daemon=True)
            monitor_thread.start()

        main()
    except Exception as e:
        Log.ERROR("An error occurred: %s" % str(e))
        globals.script_terminating = True  # Set the flag to stop monitoring thread
        cleanup(lock_file, pid_file)
        sys.exit(1)  # Terminate the script immediately