import os
import sys
from typing import List, Optional
from fastapi import FastAPI, Depends, HTTPException, status, Request
from fastapi.security import APIKeyHeader
from pydantic import BaseModel
import json
import uvicorn
from ariadne import QueryType, make_executable_schema, gql
from ariadne.asgi import GraphQL
from watchgod import run_process

# Import Log and Util classes from the lib module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from lib import Log, Util

# Load configurations from environment variables
CONFIG_FILE_PATH = os.environ.get('CONFIG_FILE_PATH', '/export/home/dpower/jag/eta_master/scripts/py/monitor/status.json')
API_KEY = os.environ.get('API_KEY', 'your-secret-api-key')
# LOG_FILE = os.environ.get('LOG_FILE', 'myapp.log')
LOG_FILE = os.getenv('LOG_FILE', '/export/home/dpower/project/log/pp_status_ws3.log')

# Configure the logger
Log.configure_logger(LOG_FILE)
logger = Log.get_logger()

# Define API key authentication scheme
api_key_header = APIKeyHeader(name='X-API-Key')

# Define data models
class ProcessData(BaseModel):
    sequence: int
    cfg_file: str
    log_file: str
    sleep_time: Optional[int] = None
    staging_folder: str
    staging_folder_file_type: str
    file_count: int
    group: str
    pid: str
    status: str

# Define GraphQL schema
type_defs = gql("""
    type ProcessData {
        sequence: Int
        cfg_file: String
        log_file: String
        sleep_time: Int
        staging_folder: String
        staging_folder_file_type: String
        file_count: Int
        group: String
        pid: String
        status: String
    }

    type Query {
        processes: [ProcessData]
    }
""")

query = QueryType()

# Helper function to load data from file
def load_data():
    if not os.path.exists(CONFIG_FILE_PATH):
        logger.error(f"File not found: {CONFIG_FILE_PATH}")
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"File not found: {CONFIG_FILE_PATH}")

    try:
        with open(CONFIG_FILE_PATH, "r") as file:
            data = json.load(file)
    except Exception as e:
        logger.error(f"Error reading data file: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error reading data file")

    return [ProcessData(**{k: v if v is not None else 0 for k, v in item.items()}) for item in data]

@query.field("processes")
def resolve_processes(*_):
    return load_data()

# Create executable schema
schema = make_executable_schema(type_defs, query)

# Create FastAPI app
app = FastAPI()

# Include GraphQL route
app.add_route("/graphql", GraphQL(schema, debug=True))

# Define REST API endpoint
@app.get("/processes", response_model=List[ProcessData], dependencies=[Depends(api_key_header)])
async def get_processes():
    try:
        return load_data()
    except HTTPException as e:
        raise e
    except Exception as e:
        logger.error(f"Error retrieving process data: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An error occurred while retrieving process data.")

# Authentication middleware
async def verify_api_key(api_key: str = Depends(api_key_header)):
    if api_key != API_KEY:
        logger.warning(f"Invalid API key: {api_key}")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key")

app.middleware("http")(verify_api_key)

# Startup event handler
@app.on_event("startup")
async def startup_event():
    logger.info("Application started")

# Shutdown event handler
@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Application shutting down")

def run_server():
    uvicorn.run("app:app", host="0.0.0.0", port=5500, reload=True)


if __name__ == "__main__":
    run_process('.', target=run_server, reloader_type='watchgod', debounce=100, stop_on_stdin_close=True, 
                callback=lambda change: change[1].endswith('.py'))

# if __name__ == "__main__":
#     uvicorn.run("app:app", host="0.0.0.0", port=5500, reload=True, reload_excludes=["*.log"])
