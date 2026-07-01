import sys
sys.path.insert(0, '/export/home/dpower/project/scripts/py/lib')
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import globals
from Log import Log
from collections import deque
from scandir import scandir
import re
from utils.file_utils import monitor_system, cleanup, signal_handler

class FolderProcessor:
    """
    A class for processing folders and identifying the deepest folder matching a specified target folder.

    This class is responsible for recursively searching through a root directory to find the deepest folder
    with the same name as the target folder. It then processes all files within the deepest matching folders.
    The class skips hidden folders and folders with names matching specified regular expressions.

    Attributes:
        root_dir (Path): The root directory to start processing from.
        target_folder (str): The folder to target within the root directory.
        file_processor (FileProcessor): An instance of the FileProcessor class to handle file processing.
        lock_file (str): The path to the lock file.
        pid_file (str): The path to the PID file.
    """

    def __init__(self, root_dir, target_folder, file_processor, lock_file, pid_file):
        """
        Initializes the FolderProcessor instance.

        Args:
            root_dir (str): The root directory to start processing from.
            target_folder (str): The folder to target within the root directory.
            file_processor (FileProcessor): An instance of the FileProcessor class to handle file processing.
            lock_file (str): The path to the lock file.
            pid_file (str): The path to the PID file.
        """
        self.root_dir = Path(root_dir)
        self.target_folder = target_folder
        self.file_processor = file_processor
        self.lock_file = lock_file
        self.pid_file = pid_file
        
    def find_process_max_depth_folders_files(self):
        """
        Finds and processes the deepest folders matching the target folder name, and processes files within them.

        This method recursively searches through the root directory to find the deepest folder with the same name
        as the target folder. It skips folders with names matching specified regular expressions. If there are no
        deepest subfolders with the same name as the target folder, and the root directory has the same name as
        the target folder, it processes the files within the root directory. Otherwise, it processes the files within
        the deepest matching folders found. If a top folder has the same name as the target folder and it has no subfolder
        with the same name, this top folder is considered the deepest subfolder of the root dir.
        """
        try:
            # Define the list of folder name regular expressions to skip
            folder_regex_patterns = globals.folder_regex_patterns

            root_dir = Path(self.root_dir)
            target_folder_name = os.path.basename(self.target_folder)

            # Get the top-level folders and filter them based on the folder_regex_patterns
            top_level_folders = [entry.path for entry in scandir(str(root_dir)) if entry.is_dir() and not entry.name.startswith('.') and not any(re.match(pattern, entry.name) for pattern in folder_regex_patterns)]

            for top_folder in top_level_folders:
                # Skip the top-level folder if its name matches the regular expressions
                if any(re.match(pattern, Path(top_folder).name) for pattern in folder_regex_patterns):
                    Log.INFO(f'Skipping top folder={top_folder} due to folder name matching regex patterns')
                    continue

                Log.INFO(f'Looking for deepest sub folder in this location={top_folder} with the same name as target={self.target_folder}')
                Log.INFO(f'Starting search for deepest subfolder in {top_folder}')

                queue = deque([(Path(top_folder), 0)])
                max_depth = -1
                max_depth_folders = []

                while queue:
                    curr_dir, depth = queue.popleft()
                    entries = (entry for entry in scandir(str(curr_dir)) if entry.is_dir() and not entry.name.startswith('.') and not any(re.match(pattern, entry.name) for pattern in folder_regex_patterns))

                    for entry in entries:
                        entry_path = Path(entry.path)
                        entry_depth = entry_path.relative_to(curr_dir).parts.count(os.sep)
                        Log.INFO(f'Processing entry: {entry_path}, depth: {entry_depth}, name: {entry.name}')

                        if entry.name == target_folder_name:
                            Log.INFO(f'Found folder with name {target_folder_name} at depth {entry_depth}')
                            if entry_depth > max_depth and not self.is_directory_empty(entry_path):
                                max_depth = entry_depth
                                max_depth_folders = [entry_path]
                                Log.INFO(f'New max depth: {max_depth}, max depth folders: {max_depth_folders}')
                            elif entry_depth == max_depth and not self.is_directory_empty(entry_path):
                                max_depth_folders.append(entry_path)
                                Log.INFO(f'Added folder to max depth folders: {max_depth_folders}')
                        queue.append((entry_path, entry_depth + 1))

                # If no subfolder with the target name was found, consider the top folder as the deepest subfolder
                if not max_depth_folders and Path(top_folder).name == target_folder_name:
                    max_depth_folders = [Path(top_folder)]

                # Check if there are deepest subfolders with the same name as the target folder
                if max_depth_folders:
                    for max_depth_folder in max_depth_folders:
                        Log.INFO(f'Processing files in maximum depth folder={max_depth_folder}')
                        self.process_files_in_folder(max_depth_folder)
                # If there are no deepest subfolders and the root directory has the same name as the target folder
                elif root_dir.name == target_folder_name:
                    Log.INFO(f'Root directory is the target folder: {root_dir}')
                    self.process_files_in_folder(root_dir)
                
                Log.INFO(f'Max depth folders : {len(max_depth_folders)}')
        except Exception as e:
            Log.ERROR(f"An error occurred during folder processing: {e}")
            cleanup(self.lock_file, self.pid_file)

    def process_files_in_folder(self, folder):
        """
        Processes the files in a folder, excluding hidden files.

        Args:
            folder (Path): The folder to process.

        This method iterates over the files in the given folder, excluding hidden files (files starting with a dot).
        For each non-hidden file, it calls the process_file_entry method of the associated FileProcessor instance.
        If an exception occurs during file processing, it logs the error and performs cleanup operations.
        """
        Log.INFO(f"Processing files in folder: {folder}")

        try:
            file_entries = (Path(entry.path) for entry in os.scandir(folder) if entry.is_file() and not entry.name.startswith('.') and not folder.name.startswith('.'))
            for file_path in file_entries:
                try:
                    self.file_processor.process_file_entry(file_path)
                except Exception as e:
                    Log.ERROR(f"Error processing file {file_path}: {e}")
                    cleanup(self.lock_file, self.pid_file)
        except Exception as e:
            Log.ERROR(f"An error occurred while processing files in folder {folder}: {e}")
            cleanup(self.lock_file, self.pid_file)

    def is_directory_empty(self, folder):
        """
        Checks if a directory is empty.

        Args:
            folder (Path): The path to the directory to check.

        Returns:
            bool: True if the directory is empty, False otherwise.

        This method uses the scandir function to iterate over the entries in the given directory.
        If the iterator is exhausted (StopIteration is raised), it means the directory is empty.
        """
        try:
            if next(os.scandir(folder)) is None:
                return True
        except StopIteration:
            return True
        return False