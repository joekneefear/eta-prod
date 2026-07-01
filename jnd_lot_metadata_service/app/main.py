from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from datetime import datetime
from pathlib import Path
import csv
import socket
from fastapi.openapi.utils import get_openapi
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.logger import get_logger

app = FastAPI(
    title="JND lot metadata service",
    description="API to extract JND technology, lotType and tpno from a jnd lot metadata file (.lot) by lot",
    version="1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Replace with specific domains in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

logger = get_logger(__name__)

@app.get(
    "/jnd-lot-metadata/lotid/{lot}",
    summary="Get JND lot metadata from lot file by lot",
    description="Returns the technology, lot type and tpno for a given lotid by reading the corresponding .lot file.",
    tags=["JND Lot Metadata"]
)
def get_lot_metadata(lot: str):
    technology = "NA"
    lot_type = "NA"
    tpno = "NA"

    try:
        lot_prefix = lot.split('.')[0]
        file_path = Path(settings.LOT_FILES_DIR) / f"{lot_prefix}.lot"
        logger.info(f"Searching file: {file_path}")

        if not file_path.exists():
            logger.error(f"File not found: {file_path}")
            return JSONResponse(status_code=404, content={
                "status": "NO_JND_LOT_METADATA_FILE",
                "errorMessage": f"File not found: {file_path}",
                "lot": lot,
                "tpno": tpno,
                "technology": technology,
                "lot_type": lot_type
            })

        matched_row = None

        with file_path.open("r", encoding="utf-8") as f:
            reader = csv.reader(f, delimiter=",")
            for row in reader:
                if row and row[0].strip() == lot:
                    matched_row = row  # Keep the last matching row

        if not matched_row:
            logger.error(f"Lot '{lot}' not found in first column of row in the file: {file_path}")
            return JSONResponse(status_code=404, content={
                "status": "NO_JND_LOT_METADATA",
                "errorMessage": f"Lot did not exist in jnd lot metadata file: {file_path}",
                "lot": lot,
                "tpno": tpno,
                "technology": technology,
                "lot_type": lot_type
            })

        if len(matched_row) < 24:
            logger.error(f"Insufficient data in matched row for lot '{lot}' in {file_path}")
            return JSONResponse(status_code=422, content={
                "status": "BAD_JND_LOT_METADATA_FILE",
                "errorMessage": "Insufficient data in the matched row",
                "lot": lot,
                "tpno": tpno,
                "technology": technology,
                "lot_type": lot_type
            })

        tpno = matched_row[1]
        technology = matched_row[16]
        if matched_row[23].strip():
            lot_type = matched_row[23]
        else:
            lot_type = "NA"

        return JSONResponse(content={
            "status": "LOT_METADATA",
            "errorMessage": None,
            "lot": lot,
            "tpno": tpno,
            "technology": technology,
            "lot_type": lot_type
        })

    except csv.Error as e:
        logger.exception(f"CSV parsing error in {file_path}: {e}")
        return JSONResponse(status_code=500, content={
            "status": "UNKNOWN",
            "errorMessage": f"CSV parsing error: {e}",
            "lot": lot,
            "tpno": tpno,
            "technology": technology,
            "lot_type": lot_type
        })

    except Exception as e:
        logger.exception("Unexpected error occurred")
        return JSONResponse(status_code=500, content={
            "status": "UNKNOWN",
            "error": f"Unexpected error: {str(e)}",
            "lot": lot,
            "tpno": tpno,
            "technology": technology,
            "lot_type": lot_type
        })
        
def custom_openapi():
    if app.openapi_schema:
        return app.openapi_schema

    hostname = socket.gethostname()
    ip_address = socket.gethostbyname(hostname)
    server_url = f"http://{hostname}:8000"

    openapi_schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )

    openapi_schema["servers"] = [
        {
            "url": server_url,
            "description": f"Dynamic server based on hostname: {hostname}"
        }
    ]

    app.openapi_schema = openapi_schema
    return app.openapi_schema

app.openapi = custom_openapi