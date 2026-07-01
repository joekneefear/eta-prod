import sys
sys.path.insert(0, '/export/home/dpower/project/scripts/py/lib')
from Log import Log
import os
import time
from pathlib import Path
import threading
from utils.file_utils import monitor_system, cleanup, signal_handler

class FileProcessor:
    """
    A class for processing files based on an age threshold and a test mode.

    This class provides functionality to delete files older than a specified age threshold
    or list the files that would have been deleted if run in test mode. It uses a lock
    to ensure thread-safety when deleting files.

    Attributes:
        DELETE_FAILED_WARNING (str): A warning message displayed when a file cannot be deleted.
        PROCESS_ERROR_MSG (str): An error message displayed when there is an issue processing a file.
        age_threshold_days (int): The age threshold in days for file deletion.
        test_mode (bool): Flag indicating whether the processor should run in test mode.
        lock (threading.Lock): A lock object to ensure thread-safe file deletion.
        lock_file (str): The path to the lock file.
        pid_file (str): The path to the PID file.
    """

    DELETE_FAILED_WARNING = "{} not found. Skipping deletion."
    PROCESS_ERROR_MSG = "Error processing file: {}"

    def __init__(self, age_threshold_days: int, test_mode: bool, lock_file, pid_file) -> None:
        """
        Initializes the FileProcessor.

        Args:
            age_threshold_days (int): The age threshold (in days) for file deletion.
            test_mode (bool): Flag to indicate whether the processor should run in test mode.
        """
        if age_threshold_days < 0:
            raise ValueError("Age threshold must be >= 0")
        self.age_threshold_days = age_threshold_days
        self.test_mode = test_mode
        self.lock = threading.Lock()
        self.lock_file = lock_file
        self.pid_file = pid_file

    def _delete_file(self, entry: Path) -> None:
        """
        Deletes a file or logs a warning if the file cannot be found.

        Args:
            entry (Path): The path to the file to be deleted.
        """
        with self.lock:
            try:
                os.remove(entry)
                Log.INFO(f"{entry} was deleted!")
            except FileNotFoundError:
                Log.WARN(self.DELETE_FAILED_WARNING.format(entry))
            except Exception as e:
                Log.ERROR(f"Error deleting {entry}, Error: {e}")
                cleanup(self.lock_file, self.pid_file)

    def __call__(self, entry: Path) -> None:
        """
        Calls the process_file_entry method.

        Args:
            entry (Path): The path of the file to process.
        """
        self.process_file_entry(entry)

    def process_file_entry(self, entry: Path) -> None:
        """
        Processes a file entry.

        Args:
            entry (Path): The path of the file to process.
        """
        try:
            # Check if the file exists before trying to process it
            if not entry.exists():
                Log.WARN(self.DELETE_FAILED_WARNING.format(entry))
                return

            file_age = self._get_file_age_days(entry)
            if file_age > self.age_threshold_days:
                Log.INFO(f"File age ({int(file_age)} days) is greater than the threshold ({self.age_threshold_days} days)")
                self._take_deletion_action(entry)
        except Exception as e:
            Log.ERROR(self.PROCESS_ERROR_MSG.format(e))
            cleanup(self.lock_file, self.pid_file)

    def _get_file_age_days(self, entry: Path) -> float:
        """
        Calculates the age of a file in days.

        Args:
            entry (Path): The path to the file.

        Returns:
            float: The age of the file in days.
        """
        mod_time = entry.stat().st_mtime
        return (time.time() - mod_time) / 86400

    def _take_deletion_action(self, entry: Path) -> None:
        """
        Deletes a file or logs a message indicating it would have been deleted in test mode.

        Args:
            entry (Path): The path to the file to be processed.
        """
        if not self.test_mode:
            self._delete_file(entry)
        else:
            Log.INFO(f"Test mode: {entry} would have been deleted")