"""
SYNOPSIS

DESCRIPTION
    Logger 

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Sep-06 - jgarcia - initial
    2023-Mar-11 - jgarcia - add support to capture message for pplogger

LICENSE
    (C) onsemi 2023 All rights reserved.
"""

import logging
import logging.config
from logging.handlers import RotatingFileHandler
import sys
import os

class Log:
    logger = None  # Static variable to hold the logger instance
    pplogger = None

    @classmethod
    def configure_logger(cls, log_file=None, pplogger=None, level="INFO"):
        # Ensure the directory for the log file exists
        if log_file:
            log_dir = os.path.dirname(log_file)
            if log_dir and not os.path.exists(log_dir):
                os.makedirs(log_dir)

        # Define the logging configuration
        logging_config = {
            'version': 1,
            'disable_existing_loggers': False,
            'formatters': {
                'standard': {
                    'format': '%(asctime)s [%(levelname)s] %(message)s',
                    'datefmt': '%Y-%m-%d %H:%M:%S',
                },
            },
            'handlers': {
                'fileHandler': {
                    'class': 'logging.handlers.RotatingFileHandler',
                    'level': level,
                    'formatter': 'standard',
                    'filename': log_file if log_file else 'myapp.log',
                    'mode': 'a',
                    'maxBytes': 10 * 1024 * 1024,  # 10 MB
                    'backupCount': 5,
                },
                'consoleHandler': {
                    'class': 'logging.StreamHandler',
                    'level': level,
                    'formatter': 'standard',
                    'stream': sys.stdout,
                },
            },
            'root': {
                'level': level,
                'handlers': ['fileHandler', 'consoleHandler'],
            },
        }

        logging.config.dictConfig(logging_config)
        cls.logger = logging.getLogger()
        cls.pplogger = pplogger
        cls.logger.info("##### Start #####")

    @classmethod
    def get_logger(cls):
        if cls.logger is None:
            cls.configure_logger()
        return cls.logger
    

    @classmethod
    def INFO(cls, msg, persist=False):
        cls.get_logger().info(msg)
        if cls.pplogger:
            if persist:
                # Force persist by appending a special marker or handling it directly in PPLogger?
                # For now, let's rely on the set_log_msg logic, but we could make it smarter.
                # Ideally, PPLogger.set_log_msg should take a 'force' param.
                # Updating to just pass it through - we might need to update PPLogger next if we want strict enforcement.
                # For this step, I'll pass it to set_log_msg if we update its signature, OR just ensure msg is passed.
                cls.pplogger.set_log_msg(msg, force=persist)
            else:
                cls.pplogger.set_log_msg(msg)

    @classmethod
    def WARN(cls, msg, persist=False):
        cls.get_logger().warning(msg)
        if cls.pplogger:
            cls.pplogger.set_log_msg(msg, force=persist)
            
    @classmethod
    def ERROR(cls, msg, exc_info=False, persist=True): # Default persist=True for errors
        cls.get_logger().error(msg, exc_info=exc_info)
        if cls.pplogger:
            cls.pplogger.set_log_msg(msg, force=persist)

    @classmethod
    def DEBUG(cls, msg, persist=False):
        cls.get_logger().debug(msg)
        if cls.pplogger:
            # DEBUG usually shouldn't clutter DB unless explicitly requested
            if persist:
                cls.pplogger.set_log_msg(msg, force=True)
