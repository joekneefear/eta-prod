
"""
SYNOPSIS

DESCRIPTION
    EpiScribe service for inserting into refdb.on_scribe

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2025-Mar-11 - jgarcia - initial
    2025-May-14 - jgarcia - static value for on_scribe.waferid_source => WAFERID_SOURCE='FROM_PCM_FILE'
    2025-Jun-05 - jgarcia - scribeid as waferid

LICENSE
    (C) onsemi 2025 All rights reserved.
"""

from sqlalchemy import Table, Column, Integer, String, Date, MetaData, select, exists
from datetime import datetime
from lib.Log import Log
from lib.Util import Util

metadata = MetaData()

ON_SCRIBE = Table(
    'ON_SCRIBE', metadata,
    Column('SCRIBEID', String(32), nullable=False),
    Column('WAFER_NUM', Integer),
    Column('LOT', String(32)),
    Column('FAB', String(64)),
    Column('INSERT_TIME', Date, default=datetime.now),
    Column('ID', Integer, primary_key=True),
    Column('WAFERID', String(32)),
    Column('STATUS', String(32)),
    Column('SCRIBEID_SOURCE', String(16)),
    Column('WAFERID_SOURCE', String(16))
)

class PowerchipEpiScribeService:
    def __init__(self, db_session, pplogger=None):
        self.db_session = db_session
        self.pplogger = pplogger

    def insert_epi_scribe_data(self, model):
        try:
            # lot_value = model.misc.get('lot', None)  # Get 'lot' value separately
            lot_value = model.header.LOT
            source_lot = model.header.SOURCE_LOT
            if source_lot.endswith(".S"):
                source_lot = source_lot[:-2]
                
            for key, scribe_id in model.misc.items():
                # Skip processing if 'lot' key is encountered (it's not an epi_scribe entry)
                if key == "lot":
                    continue
                
                # Log.INFO(f"Processing entry: Key={key}, Scribe={scribe_id}")

                # Ensure the key follows expected format
                if "-" not in key:
                    Log.WARN(f"Unexpected key format in model.misc: {key}")
                    continue  # Skip incorrect entries

                lot, wafer_num = key.split('-')

                try:
                    wafer_num = int(wafer_num)
                    wafer_num = int(f"{wafer_num:02d}")  # Ensuring two-digit format
                except ValueError:
                    Log.WARN(f"Invalid wafer_num format: {wafer_num}, skipping entry.")
                    continue

                existing_entry = self.db_session.execute(
                    select(ON_SCRIBE.c.SCRIBEID).where(ON_SCRIBE.c.SCRIBEID == scribe_id)
                ).first()

                if not existing_entry:
                    Log.INFO(f"Inserting new entry: {scribe_id}")
                    self.db_session.execute(
                        ON_SCRIBE.insert().values(
                            SCRIBEID=scribe_id,
                            WAFER_NUM=wafer_num,
                            LOT=lot_value if lot_value else lot,  # Use retrieved 'lot' value if available
                            FAB=model.header.FAB,
                            INSERT_TIME=datetime.now(),
                            WAFERID=scribe_id,
                            STATUS='MANUAL',
                            WAFERID_SOURCE='FROM_PCM_FILE'
                        )
                    )
                    self.db_session.commit()
        except Exception as e:
            Log.ERROR(f"Unexpected error in insert_epi_scribe_data: {e}")
            Util.dp_exit(1, pplogger=self.pplogger, error="Unexpected error in insert_epi_scribe_data: " + str(e) + "!")
        finally:
            self.db_session.close()
