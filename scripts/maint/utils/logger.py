import logging
from logging.handlers import RotatingFileHandler

def configure_logging(log_level, log_file):
    """
    Configure the logging system to write logs to a file and the console.

    Args:
        log_level (int): The logging level to set for the logger.
            Can be one of the following levels: logging.DEBUG, logging.INFO, logging.WARNING, logging.ERROR, logging.CRITICAL.
        log_file (str): The path to the log file where logs will be written.

    Returns:
        logging.Logger: The configured logger instance.

    This function sets up the logging system to write logs to a file and the console simultaneously.
    The file handler uses a RotatingFileHandler, which will create new log files when the current file
    reaches a maximum size of 1 MB (10^6 bytes). A maximum of 10 backup log files will be kept.

    The log messages will be formatted with a timestamp, log level, and the message text.
    The logger will be set to the specified log level, and both the file and stream handlers will be added to it.
    """
    formatter = logging.Formatter("%(asctime)s %(levelname)s: %(message)s")

    # Create a file handler with log rotation
    file_handler = RotatingFileHandler(log_file, maxBytes=10**6, backupCount=10)
    file_handler.setLevel(log_level)
    file_handler.setFormatter(formatter)

    # Create a stream handler for console output
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)

    # Configure the logger
    logger = logging.getLogger()
    logger.setLevel(log_level)
    logger.addHandler(file_handler)
    logger.addHandler(stream_handler)

    return logger