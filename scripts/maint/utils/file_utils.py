import os
import psutil
import time
import sys
import globals

lock_file = None
pid_file = None

def monitor_system():
    """
    Monitor system resources (CPU usage, memory usage, and load average) and print the current process ID.

    This function runs in an infinite loop, monitoring and printing system resource usage and the current process ID
    until the `globals.script_terminating` flag is set to True. If the load average exceeds 5, it prints a warning
    message indicating high system load.

    If an exception occurs during monitoring, it sets the `globals.script_terminating` flag to True, calls the
    `cleanup` function, and terminates the script immediately.

    The function sleeps for 7 seconds between each monitoring iteration to prevent excessive resource usage.
    Once the monitoring loop is terminated, it prints a message indicating that the system monitoring thread has stopped.
    """
    pid = os.getpid()
    while not globals.script_terminating:
        try:
            cpu_percent = psutil.cpu_percent()
            memory_percent = psutil.virtual_memory().percent
            load_average = os.getloadavg()[0]  # Get the 1-minute load average
            print(f"PID: {pid} | CPU Usage: {cpu_percent}% | Memory Usage: {memory_percent}% | Load Average: {load_average}")
            if load_average > 5:
                print("Load average exceeds 5. Script may be causing high system load.")
        except Exception as e:
            print("An error occurred in system monitoring thread: %s" % str(e))
            globals.script_terminating = True  # Set the flag to stop monitoring thread
            cleanup()
            sys.exit(1)  # Terminate the script immediately

        # Sleep for .5 seconds before next monitoring
        time.sleep(7)

    print("System monitoring thread stopped.")

def cleanup(lock_file, pid_file):
    """
    Clean up by deleting the lock file and PID file.

    Args:
        lock_file (str): The path to the lock file.
        pid_file (str): The path to the PID file.

    This function checks if the lock file and PID file exist, and if they do, it deletes them.
    """
    # Delete the lock file
    if lock_file and os.path.exists(lock_file):
        os.remove(lock_file)

    # Delete the PID file
    if pid_file and os.path.exists(pid_file):
        os.remove(pid_file)

def signal_handler(lock_file, pid_file):
    """
    Create a signal handler function to handle Ctrl+C (SIGINT) signal.

    Args:
        lock_file (str): The path to the lock file.
        pid_file (str): The path to the PID file.

    Returns:
        function: A function that handles the Ctrl+C (SIGINT) signal.

    This function returns a nested function `_handler` that is intended to be used as a signal handler for the
    Ctrl+C (SIGINT) signal. When the signal is received, the `_handler` function prints a termination message,
    sets the `globals.script_terminating` flag to True, calls the `cleanup` function with the provided lock file
    and PID file paths, and exits the script with a status code of 0.
    """
    def _handler(signal, frame):
        print('You pressed Ctrl+C! Terminating...')
        globals.script_terminating = True  # Set the global flag to stop monitoring
        # Perform any other necessary cleanup here
        cleanup(lock_file, pid_file)  # Call the cleanup function
        sys.exit(0)  # Exit the script with status code 0

    return _handler