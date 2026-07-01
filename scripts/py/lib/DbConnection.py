"""
SYNOPSIS

DESCRIPTION
    DAO class encapsulating the logic for accessing the database

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-Mar-11 - jgarcia - initial

LICENSE
    (C) onsemi 2025 All rights reserved.
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

class DbConnection:
    def __init__(self, connection_string):
        self.engine = create_engine(connection_string)
        self.Session = sessionmaker(bind=self.engine)

    def get_session(self):
        return self.Session()