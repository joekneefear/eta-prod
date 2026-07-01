"""
SYNOPSIS

DESCRIPTION
    PPLog model

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-01-01 - jgarcia - initial

LICENSE
    (C) onsemi 2025 All rights reserved.
"""

from sqlalchemy import Column, String, Integer, TIMESTAMP, LargeBinary, func
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime

# Define the base class for ORM models
Base = declarative_base()

# Define the PP_LOG model
class PPLog(Base):
    __tablename__ = 'PP_LOG'
    __table_args__ = {'implicit_returning': False}

    PP_LOG_ID = Column(LargeBinary(16), primary_key=True, default=func.sys_guid())  
    LOT = Column(String(32))
    ENVIRONMENT = Column(String(32))
    PROCESS_DATETIME = Column(TIMESTAMP)  # Changed from Date to TIMESTAMP
    PROCESS_CODE = Column(Integer)
    FILE_NAME = Column(String(255))
    OUTPUT_DIRECTORY = Column(String(255))
    LOG_MESSAGE = Column(String(2000))
    INSERT_ID = Column(String(25), nullable=True)
    MAP_ID = Column(String(25), nullable=True)
    WAFER_NUM = Column(String(255), nullable=True)
    ERROR_CODE = Column(String(255))
    PROGRAM_CLASS = Column(Integer, nullable=True)
    SITE = Column(String(100))
    PROCESS_DATETIME_ADJUST = Column(TIMESTAMP)  # Changed from Date to TIMESTAMP
    LIMIT_FILE_NAME = Column(String(255), nullable=True)
    PROGRAM_NAME = Column(String(255))
    EXTENSION = Column(String(100))
    MD5 = Column(String(100))
    PATH = Column(String(255))
    SCRIPT = Column(String(255))

    def __init__(self, LOT, ENVIRONMENT, PROCESS_DATETIME, PROCESS_CODE, FILE_NAME, OUTPUT_DIRECTORY, LOG_MESSAGE, 
                 INSERT_ID, MAP_ID, WAFER_NUM, ERROR_CODE, PROGRAM_CLASS, SITE, PROCESS_DATETIME_ADJUST, 
                 LIMIT_FILE_NAME, PROGRAM_NAME, EXTENSION, MD5, PATH, SCRIPT):
        self.LOT = LOT
        self.ENVIRONMENT = ENVIRONMENT
        self.PROCESS_DATETIME = PROCESS_DATETIME
        self.PROCESS_CODE = self.nullify_empty(PROCESS_CODE)
        self.FILE_NAME = FILE_NAME
        self.OUTPUT_DIRECTORY = OUTPUT_DIRECTORY
        self.LOG_MESSAGE = LOG_MESSAGE
        self.INSERT_ID = self.nullify_empty(INSERT_ID)
        self.MAP_ID = self.nullify_empty(MAP_ID)
        self.WAFER_NUM = self.nullify_empty(WAFER_NUM)
        self.ERROR_CODE = ERROR_CODE
        self.PROGRAM_CLASS = self.validate_integer(PROGRAM_CLASS)
        self.SITE = SITE
        self.PROCESS_DATETIME_ADJUST = PROCESS_DATETIME_ADJUST
        self.LIMIT_FILE_NAME = self.nullify_empty(LIMIT_FILE_NAME)
        self.PROGRAM_NAME = PROGRAM_NAME
        self.EXTENSION = EXTENSION
        self.MD5 = MD5
        self.PATH = PATH
        self.SCRIPT = SCRIPT

    @staticmethod
    def validate_datetime(dt_value):
        """Ensure TIMESTAMP values are correctly passed as datetime objects."""
        if isinstance(dt_value, datetime):  # Already a datetime object
            return dt_value
        if isinstance(dt_value, str):  # Convert from string if needed
            try:
                return datetime.strptime(dt_value, '%Y-%m-%d %H:%M:%S')
            except ValueError:
                return None
        return None  # Return None if input is invalid

    @staticmethod
    def validate_integer(value):
        """Ensure numeric fields receive valid numbers or None."""
        if value in ["", "NA", None]:  # Handle non-numeric cases
            return None
        try:
            return int(value)
        except ValueError:
            return None

    @staticmethod
    def nullify_empty(value):
        """Convert empty string values to None."""
        return None if value == "" else value