import os
import sys
from typing import List, Optional
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel
import json
import uvicorn
import strawberry
# Import Log and Util classes from the lib module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from lib import Log, Util

# Load configurations from environment variables
CONFIG_FILE_PATH = os.environ.get('CONFIG_FILE_PATH', '/export/home/dpower/jag/eta_master/scripts/py/monitor/status.json')
API_KEY = os.environ.get('API_KEY', 'your-secret-api-key')
LOG_FILE = os.environ.get('LOG_FILE', 'pp_status_ws.log')

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

@strawberry.type
class ProcessDataGraphQL:
    sequence: int
    cfg_file: str
    log_file: str
    sleep_time: Optional[int]
    staging_folder: str
    staging_folder_file_type: str
    file_count: int
    group: str
    pid: str
    status: str

# Helper function to load data from file
def load_data():
    if not os.path.exists(CONFIG_FILE_PATH):
        logger.error(f"File not found: {CONFIG_FILE_PATH}")
        raise ValueError(f"File not found: {CONFIG_FILE_PATH}")

    try:
        with open(CONFIG_FILE_PATH, "r") as file:
            data = json.load(file)
    except Exception as e:
        logger.error(f"Error reading data file: {e}")
        raise e

    return [ProcessData(**{k: v if v is not None else 0 for k, v in item.items()}) for item in data]

# Define GraphQL schema and resolver
@strawberry.type
class Query:
    @strawberry.field
    def processes(self) -> list[ProcessDataGraphQL]:
        return [ProcessDataGraphQL(**{k: v if v is not None else 0 for k, v in item.dict().items()}) for item in load_data()]

schema = strawberry.Schema(Query)

# Create FastAPI app
app = FastAPI()

# Include GraphQL router
graphql_app = strawberry.fastapi.GraphQLRouter(schema)
app.include_router(graphql_app, prefix="/graphql", dependencies=[Depends(api_key_header)])

# Define REST API endpoint
@app.get("/processes", response_model=List[ProcessData], dependencies=[Depends(api_key_header)])
async def get_processes():
    try:
        return load_data()
    except Exception as e:
        logger.error(f"Error retrieving process data: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An error occurred while retrieving process data.")

# Authentication middleware
async def verify_api_key(api_key: str = Depends(api_key_header)):
    if api_key != API_KEY:
        logger.warning(f"Invalid API key: {api_key}")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key")

# Startup event handler
@app.on_event("startup")
async def startup_event():
    logger.info("Application started")

# Shutdown event handler
@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Application shutting down")

if __name__ == "__main__":
    uvicorn.run("app:app", host="0.0.0.0", port=5500, reload=True)