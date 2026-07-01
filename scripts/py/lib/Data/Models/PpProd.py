from sqlalchemy import Column, String, Integer, Date, Float
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class PpProd(Base):
    __tablename__ = 'PP_PROD'
    PRODUCT = Column(String(32), primary_key=True)
    ITEM_TYPE = Column(String(15))
    FAB = Column(String(32))
    FAB_DESC = Column(String(50))
    AFM = Column(String(45))
    PROCESS = Column(String(32))
    FAMILY = Column(String(32))
    PACKAGE = Column(String(32))
    GDPW = Column(Integer)
    WF_UNITS = Column(String(32))
    WF_SIZE = Column(Float)
    DIE_UNITS = Column(String(32))
    DIE_WIDTH = Column(Float)
    DIE_HEIGHT = Column(Float)
    INSERT_TIME = Column(Date)
    ID = Column(Integer, autoincrement=True)