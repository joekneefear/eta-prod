from sqlalchemy import Column, String, Integer, Date, LargeBinary, func
from sqlalchemy.ext.declarative import declarative_base

# Define the base class for the ORM models
Base = declarative_base()

# Define the PP_LOG model
class PPLog(Base):
    __tablename__ = 'PP_LOG'
    __table_args__ = {'implicit_returning': False}  # Corrected typo here
    PP_LOG_ID = Column(LargeBinary(16), primary_key=True, default=func.sys_guid())
    LOT = Column(String(32))
    ENVIRONMENT = Column(String(32))
    PROCESS_DATETIME = Column(Date)
    PROCESS_CODE = Column(Integer)
    FILE_NAME = Column(String(255))
    OUTPUT_DIRECTORY = Column(String(255))
    LOG_MESSAGE = Column(String(4000))
    INSERT_ID = Column(String(25))
    MAP_ID = Column(String(25))
    WAFER_NUM = Column(String(255))
    ERROR_CODE = Column(String(255))
    PROGRAM_CLASS = Column(Integer)
    SITE = Column(String(100))
    PROCESS_DATETIME_ADJUST = Column(Date)
    LIMIT_FILE_NAME = Column(String(255))
    PROGRAM_NAME = Column(String(255))
    EXTENSION = Column(String(100))
    MD5 = Column(String(100))
    PATH = Column(String(255))
    SCRIPT = Column(String(255))

    def __init__(self, LOT, ENVIRONMENT, PROCESS_DATETIME, PROCESS_CODE, FILE_NAME, OUTPUT_DIRECTORY, LOG_MESSAGE, INSERT_ID, MAP_ID, WAFER_NUM, ERROR_CODE, PROGRAM_CLASS, SITE, PROCESS_DATETIME_ADJUST, LIMIT_FILE_NAME, PROGRAM_NAME, EXTENSION, MD5, PATH, SCRIPT):
        self.LOT = LOT
        self.ENVIRONMENT = ENVIRONMENT
        self.PROCESS_DATETIME = PROCESS_DATETIME
        self.PROCESS_CODE = PROCESS_CODE
        self.FILE_NAME = FILE_NAME
        self.OUTPUT_DIRECTORY = OUTPUT_DIRECTORY
        self.LOG_MESSAGE = LOG_MESSAGE
        self.INSERT_ID = INSERT_ID
        self.MAP_ID = MAP_ID
        self.WAFER_NUM = WAFER_NUM
        self.ERROR_CODE = ERROR_CODE
        self.PROGRAM_CLASS = PROGRAM_CLASS
        self.SITE = SITE
        self.PROCESS_DATETIME_ADJUST = PROCESS_DATETIME_ADJUST
        self.LIMIT_FILE_NAME = LIMIT_FILE_NAME
        self.PROGRAM_NAME = PROGRAM_NAME
        self.EXTENSION = EXTENSION
        self.MD5 = MD5
        self.PATH = PATH
        self.SCRIPT = SCRIPT