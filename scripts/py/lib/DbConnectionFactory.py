"""
SYNOPSIS

DESCRIPTION
    DbConnectionFactory class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-Mar-11 - jgarcia - initial

LICENSE
    (C) onsemi 2025 All rights reserved.
"""


from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import os
import snowflake.connector
from lib.DbConnection import DbConnection

class DbConnectionFactory:
    @staticmethod
    def create_db_connection(db_type, config=None):
        if db_type == 'oracle':
            if config:
                # Use config keys: user, password, port, sid, server_name
                db_user = config.get('user', 'refdb')
                db_pass = config.get('password', '88sgX%#$29-azx')
                db_host = config.get('server_name', 'exnprd-db.onsemi.com')
                db_port = config.get('port', '1729')
                db_sid = config.get('sid', 'EXNPRD')
                db_service_name = config.get('service_name' , 'EXNPRD.onsemi.com')
                
                connection_string = f'oracle+cx_oracle://{db_user}:{db_pass}@{db_host}:{db_port}/?service_name={db_service_name}'
            else:
                # Fallback to original setup using TNS and env vars
                db_tns = os.getenv('REFDB_TNS', 'exnprd-db.onsemi.com:1729/EXNPRD.onsemi.com')
                db_user = os.getenv('REFDB_USER', 'refdb')
                db_pass = os.getenv('REFDB_PASS', '88sgX%#$29-azx')
                
                db_tns = db_tns.replace("dbi:Oracle://", "")
                host_port, service_name = db_tns.split("/")
                connection_string = f'oracle+cx_oracle://{db_user}:{db_pass}@{host_port}/?service_name={service_name}'
            
            return DbConnection(connection_string)
        
        elif db_type == 'snowflake':
            if config:
                sf_user = config.get('user', 'MFG_PRD_RPT_EXENSIO_USER')
                sf_pass = config.get('password', '5)Day=323fFd')
                sf_account = config.get('server_name', 'onsemi.west-us-2.azure.snowflakecomputing.com')
            else:
                sf_user = os.getenv('SNOW_USER', 'MFG_PRD_RPT_EXENSIO_USER')
                sf_pass = os.getenv('SNOW_PASS', '5)Day=323fFd')
                sf_account = os.getenv('SNOWFLAKE_ACCOUNT', 'onsemi.west-us-2.azure.snowflakecomputing.com')

            connection = snowflake.connector.connect(
                user=sf_user,
                password=sf_pass,
                account=sf_account
            )
            return connection

        else:
            raise ValueError(f"Unsupported database type: {db_type}")
