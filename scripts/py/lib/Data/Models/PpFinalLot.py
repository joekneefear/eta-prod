from sqlalchemy import Column, String, Date
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class PpFinalLot(Base):
    __tablename__ = 'PP_FINALLOT'
    LOT = Column(String(32), primary_key=True)
    LOT_OWNER = Column(String(32))
    PRODUCT = Column(String(32))
    DATE_CODE = Column(String(32))
    INSERT_TIME = Column(Date)