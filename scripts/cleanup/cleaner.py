#!/usr/bin/env python3
"""
Script for cleaning x days old files in a specified directory and target folder.
2023-05-22: jgarcia: initial
2023-Dec-22: jgarcia: Used pathlib for faster path handling, Thread pool executor to parallelize folder depth calculation,
Cached results using lru_cache decorator for memoization
2023-Dec-27: jgarcia: refactor to OOP style. introduce batch deletion, logging thread safety.
2024-Jan-05: jgarcia: used depth first search algorithm in finding maximum depth folder, consistent logging levels, logging verbosity, 
                      specific exception handling, asynchronous, usage configurability, and documentation.
2024-Jan-08: jgarcia: added configurable metrics, profiling
2024-Jan-09: jgarcia: Flush to console immediately for specific log messages when log_buffer is NOT >= log_batch_size which is set to 100
"""
import logging
import logging.handlers as handlers
import argparse
from datetime import datetime
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor, as_completed
import threading
import traceback
import multiprocessing
from multiprocessing import Manager
from functools import lru_cache
import asyncio
import cProfile
import time
import hashlib
import os
import gzip

class Cleaner:
    """
    Main cleaner class to delete files based on age.

    Attributes:
        root_dir (Path): Root directory path to start processing.
        target_folders (str): Name of target folders to process.
        file_age (int): Age thresholds for deleting files.
        logfile (str): Log file path.
        test (bool): Whether to run in test mode.
        executor_type (str): 'thread' or 'process'.
        concurrency_level (int): Number of parallel workers.
        log_batch_size (int): Number of logs to buffer before writing.
        log_verbose (bool): Enable verbose logging.
        metrics_logfile (str): Metrics log file path.
        last_metrics_log_time (float): Timestamp of last metrics log.
        checked_checksums (set): Tracks processed file checksums.
        log_buffer (list): Buffer to batch logs.
        log_lock (Lock): Lock when writing logs.
        logger (Logger): Logger instance.

    Methods:
        configure_logging: Sets up logging.
        log_info: Logs informational message.
        log_warning: Logs warnings.
        log_error: Logs errors.
        log_metrics: Logs metrics.
        compress_logs: Compresses existing logs.
        delete_file_async: Deletes a file async.
        process_file_entry_async: Processes a file async.
        check_file_async: Checks files in folder async.
        calculate_checksum: Gets file checksum.
        delete_files: Deletes files.
        process_max_depth_folders_async: Starts folder processing.
        dfs: Helper to find max depth folders.
        find_max_depth_folders_parallel: Finds max depth folders.
        main: Main function.

    Class Methods:
        get_default_concurrency_level: Gets default concurrency level.
        LOG_BATCH_SIZE (int): Default batch size for logs.
        DEFAULT_CONCURRENCY_LEVEL (int): Default concurrency level.
        MAX_LOG_BYTES (int): Max bytes per log file.

    Static Methods:
        dfs: Depth first search helper.
    """
    
    
    MAX_LOG_BYTES = 10*1024*1024
    DEFAULT_CONCURRENCY_LEVEL = multiprocessing.cpu_count()
    LOG_BATCH_SIZE = 100

    def __init__(self, root_dir, target_folders, file_age, logfile, test, executor_type='thread', concurrency_level=None, log_batch_size=None, log_verbose=False, enable_metrics=False):
        """
        Initialize Cleaner object.

        Parameters:
        - root_dir (str): Root directory path to start processing
        - target_folders (str): Name of target folders to process 
        - file_age (int): Age thresholds for deleting files
        - logfile (str): Log file path
        - test (bool): Whether to run in test mode
        - executor_type (str): 'thread' or 'process'
        - concurrency_level (int): Number of parallel workers
        - log_batch_size (int): Number of logs to buffer before writing 
        - log_verbose (bool): Enable verbose logging
        - enable_metrics(bool): Enable metrics 
        """
        self.root_dir = Path(root_dir)
        self.target_folders = target_folders
        self.file_age = file_age
        self.logfile = logfile
        self.test = test
        self.executor_type = executor_type
        self.concurrency_level = concurrency_level or self.get_default_concurrency_level()
        self.log_batch_size = log_batch_size or self.LOG_BATCH_SIZE
        self.log_verbose = log_verbose
        self.enable_metrics = enable_metrics
        self.metrics_logfile = f"{self.logfile}_metrics.log"
        self.last_metrics_log_time = 0
        self.checked_checksums = set()  # Store checksums to avoid duplicate deletions
        self.configure_logging()
        self.log_buffer = []
        self.log_lock = threading.Lock()

    @classmethod
    def get_default_concurrency_level(cls):
        """
        Get the default concurrency level.

        Returns:
        int: Default concurrency level.
        """
        return min(cls.DEFAULT_CONCURRENCY_LEVEL, multiprocessing.cpu_count())

    def configure_logging(self):
        """
        Set up logging configuration.
        """
        self.logger = logging.getLogger()
        self.logger.setLevel(logging.DEBUG if self.log_verbose else logging.INFO)
        formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")

        file_handler = handlers.RotatingFileHandler(self.logfile, maxBytes=self.MAX_LOG_BYTES, backupCount=5)
        file_handler.setFormatter(formatter)
        self.logger.addHandler(file_handler)

        err_handler = handlers.TimedRotatingFileHandler(f"{self.logfile}_err.log", when="m", interval=1, backupCount=0)
        err_handler.setFormatter(formatter)
        self.logger.addHandler(err_handler)

        stream_handler = logging.StreamHandler()
        stream_handler.setFormatter(formatter)
        self.logger.addHandler(stream_handler)

    def log_info(self, message):
        """
        Log informational message.

        Parameters:
        - message (str): Informational message to log.
        """
        with self.log_lock:
            self.log_buffer.append(message)
            if len(self.log_buffer) >= self.log_batch_size:
                self.logger.info('\n'.join(self.log_buffer))
                self.log_buffer = []
            else:
                # Flush to console immediately for specific log messages
                print(message)
        # with self.log_lock:
        #     self.logger.info(message)

    def log_warning(self, message):
        """
        Log warning message.

        Parameters:
        - message (str): Warning message to log.
        """
        with self.log_lock:
            self.logger.warning(message)

    def log_error(self, message, exc_info=False):
        """
        Log error message.

        Parameters:
        - message (str): Error message to log.
        - exc_info (bool): Whether to include exception info.
        """
        with self.log_lock:
            self.logger.error(message, exc_info=exc_info)

    def log_metrics(self, message):
        """
        Log metrics.

        Parameters:
        - message (str): Metrics message to log.
        """
        if self.enable_metrics:  # Check if metrics logging is enabled
            with open(self.metrics_logfile, 'a') as metrics_file:
                metrics_file.write(f"{message}\n")
                
    def compress_logs(self):
        """
        Compress existing logs.
        """
        log_files = [self.logfile, f"{self.logfile}_err.log"]

        for log_file in log_files:
            with open(log_file, 'rb') as f_in, gzip.open(f"{log_file}.gz", 'wb') as f_out:
                f_out.writelines(f_in)

            # Close the original log file explicitly
            open(log_file, 'w').close()

        self.log_info("Logs compressed successfully.")

    async def delete_file_async(self, entry):
        """
        Delete a file asynchronously.

        Parameters:
        - entry (Path): File path to delete.
        """
        try:
            await asyncio.to_thread(entry.unlink)
            self.log_info(f"{entry} was deleted!!!")
        except FileNotFoundError:
            self.log_warning(f"{entry} not found. Skipping deletion.")
        except Exception as e:
            self.log_error(f"Error deleting file: {e}", exc_info=True)

    async def process_file_entry_async(self, entry, age):
        """
        Process a file entry asynchronously.

        Parameters:
        - entry (Path): File path to process.
        - age (int): Age threshold for deleting files.
        """
        try:
            file_modification_time = datetime.fromtimestamp(entry.stat().st_mtime)
            file_age = datetime.today() - file_modification_time
            log_info = f"file={entry}||tday={datetime.today()}||fileMod={file_modification_time}||fileAge={file_age.days}"

            self.log_info(log_info)

            if file_age.days >= age:
                self.log_info(f"file age={file_age.days} in days is greater or equal to threshold={age}")

                if not self.test:
                    checksum = self.calculate_checksum(entry)
                    if checksum not in self.checked_checksums:
                        await self.delete_file_async(entry)
                        self.checked_checksums.add(checksum)

        except FileNotFoundError:
            self.log_warning(f"{entry} does not exist. Skipping deletion.")
        except Exception as e:
            self.log_error(f"Error evaluating file age: {e}, Entry: {entry}\n{traceback.format_exc()}")

    async def check_file_async(self, max_depth_target_folder, age):
        """
        Check files in a folder asynchronously.

        Parameters:
        - max_depth_target_folder (Path): Folder path to check.
        - age (int): Age threshold for deleting files.
        """
        start_time = time.time()
        entries = [entry for entry in max_depth_target_folder.iterdir() if entry.is_file()]
        tasks = [self.process_file_entry_async(entry, age) for entry in entries]
        await asyncio.gather(*tasks)
        end_time = time.time()
        elapsed_time = end_time - start_time
        files_scanned_per_sec = len(entries) / elapsed_time
        # self.log_info(f"Files scanned per second: {files_scanned_per_sec:.2f}")
        self.log_metrics(f"Files scanned per second: {files_scanned_per_sec:.2f}")
        self.log_metrics(f"Files Scanned in {max_depth_target_folder}: {len(entries)}, Time: {elapsed_time:.2f} seconds")

    def calculate_checksum(self, file_path):
        """
        Calculate checksum of a file.

        Parameters:
        - file_path (Path): File path to calculate checksum.

        Returns:
        str: File checksum.
        """
        hasher = hashlib.md5()
        with open(file_path, 'rb') as file:
            for chunk in iter(lambda: file.read(4096), b""):
                hasher.update(chunk)
        return hasher.hexdigest()

    def delete_files(self, files):
        """
        Delete files in batches.

        Parameters:
        - files (list): List of files to delete.
        """
        executor = ProcessPoolExecutor() if self.executor_type == 'process' else ThreadPoolExecutor()

        try:
            batch_size = max(1, min(len(files), self.concurrency_level))
            with executor as exec:
                batches = [files[i:i + batch_size] for i in range(0, len(files), batch_size)]
                futures = [exec.submit(self._delete_batch, batch) for batch in batches]

                for future in as_completed(futures):
                    try:
                        future.result()
                    except Exception as e:
                        self.log_error(f"Error deleting files in batch: {e}", exc_info=True)

        except Exception as e:
            self.log_error(f"Error deleting files: {e}", exc_info=True)

    def _delete_batch(self, batch):
        """
        Delete files in a batch.

        Parameters:
        - batch (list): List of files to delete.
        """
        try:
            for file in batch:
                file.unlink()
                self.log_info(f"{file} was deleted!!!")

        except FileNotFoundError:
            self.log_warning("Batch contains a file that does not exist. Skipping batch deletion.")

        except Exception as e:
            self.log_error(f"Error deleting files in batch: {e}", exc_info=True)
    
    async def process_max_depth_folders_async(self, max_depth_target_dir_folders):
        """
        Process max depth folders asynchronously.

        Parameters:
        - max_depth_target_dir_folders (list): List of max depth folders.
        """
        total_files_processed = 0
        total_processing_time = 0

        tasks = [self.check_file_async(entry, self.file_age) for entry in max_depth_target_dir_folders]
        start_time = time.time()

        try:
            await asyncio.gather(*tasks)
        except Exception as e:
            self.log_error(f"Error processing max depth folders: {e}", exc_info=True)

        end_time = time.time()
        total_processing_time = end_time - start_time

        for task in tasks:
            total_files_processed += len(task._result) if hasattr(task, '_result') else 0

        files_processed_per_sec = total_files_processed / total_processing_time if total_processing_time > 0 else 0
        self.log_info(f"Files processed per second: {files_processed_per_sec:.2f}")
        self.log_metrics(f"Total Files Processed: {total_files_processed}, Total Processing Time: {total_processing_time:.2f} seconds")     
        
    @staticmethod
    def dfs(current_path, current_depth, target_folder, result_list):
        """
        Depth-first search to find max depth folders.

        Parameters:
        - current_path (Path): Current path to check.
        - current_depth (int): Current depth in the directory tree.
        - target_folder (str): Target folder name.
        - result_list (list): Shared list to store max depth folders.
        """
        if current_path.is_dir():
            subfolders = current_path.iterdir()

            if current_path.name == target_folder and not any(subfolder.is_dir() for subfolder in subfolders):
                result_list.append(current_path)

            for subfolder in subfolders:
                Cleaner.dfs(subfolder, current_depth + 1, target_folder, result_list)

    def find_max_depth_folders_parallel(self, directory, target_folder):
        """
        Find max depth folders in parallel.

        Parameters:
        - directory (str): Root directory.
        - target_folder (str): Target folder name.

        Returns:
        list: List of max depth folders.
        """
        manager = Manager()
        result_list = manager.list()

        start_path = Path(directory)

        executor_type = self.executor_type
        if executor_type == 'process':
            result = self.dfs(start_path, 1, target_folder, result_list)
            return list(result_list)
        else:
            executor = ThreadPoolExecutor()
            with executor as exec:
                futures = [exec.submit(Cleaner.dfs, start_path, 1, target_folder, result_list)]

                for future in as_completed(futures):
                    try:
                        future.result()
                    except Exception as e:
                        self.log_error(f"Error finding max depth folders: {e}", exc_info=True)

            return list(result_list)

    def main(self):
        """
        Main method to execute the cleaning process.

        Raises:
            FileNotFoundError: If the root directory or target folders are not found.
            KeyboardInterrupt: If the script is interrupted, it logs a warning.
            Exception: For other unexpected errors, it logs the error.

        Note:
            The function logs metrics for script start and exceptions.
        """
        
        try:
            if not self.root_dir.exists():
                raise FileNotFoundError("Root directory or target folders not found.")
            self.log_metrics("Script started")

            # self.compress_logs()

            max_depth_folders_of_interest = self.find_max_depth_folders_parallel(self.root_dir, self.target_folders)
            
            if not max_depth_folders_of_interest or not any(self.root_dir.iterdir()):
                self.log_info("No max depth folders found.")
                return
                
            self.log_info(
                f"Root_dir={self.root_dir} has a total of {len(max_depth_folders_of_interest)} max depth folders that we are interested (has the same name as {self.target_folders}).")

            start_time = time.time()
            # self.process_max_depth_folders_async(max_depth_folders_of_interest)
            # asyncio.run(self.process_max_depth_folders_async(max_depth_folders_of_interest))
            loop = asyncio.get_event_loop()
            loop.run_until_complete(self.process_max_depth_folders_async(max_depth_folders_of_interest))
            end_time = time.time()
            elapsed_time = end_time - start_time
            files_deleted_per_sec = len(max_depth_folders_of_interest) / elapsed_time
            self.log_info(f"Files deleted per second: {files_deleted_per_sec:.2f}")
            self.log_metrics(f"Files Deleted: {len(max_depth_folders_of_interest)}, Time: {elapsed_time:.2f} seconds")

        except FileNotFoundError as e:
            self.log_error(f"Error in main function: {e}", exc_info=True)
            raise
        except KeyboardInterrupt:
            self.log_warning("Script interrupted. Cleaning up is necessary.")
        except Exception as e:
            self.log_error(f"Error in main function: {e}", exc_info=True)
            raise
        
def parse_arguments():
    """
    Parse command line arguments.

    Returns:
    Namespace: Parsed arguments.
    """
    parser = argparse.ArgumentParser(description='Clean files based on age in specified folders.')
    parser.add_argument('--root_dir', required=True, help='Root directory to start the cleaning process.')
    parser.add_argument('--target_folder', required=True, help='Target folders to clean.')
    parser.add_argument('--file_age', required=True, type=int, help='File age thresholds in days for each target folder.')
    parser.add_argument('--logfile', default='cleaner.log', help='Specify the logfile name. Default is cleaner.log.')
    parser.add_argument('--test', action='store_true', help='Run in test mode. Files will not be deleted.')
    parser.add_argument('--executor_type', choices=['thread', 'process'], default='thread', help='Executor type for file deletion. Default is thread.')
    parser.add_argument('--concurrency_level', type=int, help='Specify the concurrency level. Default is the number of CPU cores.')
    parser.add_argument('--log_batch_size', type=int, help='Specify the log batch size. Default is 100.')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose logging.')
    parser.add_argument('--enable_metrics', action='store_true', help='Enable metrics logging.')  # Added enable_metrics argument
    parser.add_argument('--profile', action='store_true', help='Enable profiling.')

    return parser.parse_args()



def main():
    """
    Main entry point for the script.
    """
    args = parse_arguments()
    cleaner = Cleaner(args.root_dir, args.target_folder, args.file_age, args.logfile, args.test, args.executor_type, args.concurrency_level, log_batch_size=args.log_batch_size, log_verbose=args.verbose, enable_metrics=args.enable_metrics)

    # pr = cProfile.Profile()
    # pr.enable()
    if args.profile:
        pr = cProfile.Profile()
        pr.enable()

    cleaner.main()

    # pr.disable()
    # pr.print_stats(sort='cumulative')
    if args.profile:
        pr.disable()
        pr.print_stats(sort='cumulative')

if __name__ == '__main__':
    main()
