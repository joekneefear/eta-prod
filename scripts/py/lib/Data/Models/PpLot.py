from sqlalchemy import Column, String, Integer, Date
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class PpLot(Base):
    __tablename__ = 'PP_LOT'
    LOT = Column(String(32), primary_key=True)
    PARENT_LOT = Column(String(32))
    PRODUCT = Column(String(32))
    LOT_OWNER = Column(String(32))
    PARENT_PRODUCT = Column(String(32))
    SOURCE_LOT = Column(String(32))
    INSERT_TIME = Column(Date)
    ID = Column(Integer, autoincrement=True)