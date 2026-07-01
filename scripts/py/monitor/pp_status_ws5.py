import os
import sys
from typing import List, Optional
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel
import json
import uvicorn
from ariadne import gql, QueryType, make_executable_schema
from ariadne.asgi import GraphQL

# Import Log and Util classes from the lib module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from lib import Log, Util

# Load configurations from environment variables
CONFIG_FILE_PATH = os.environ.get('CONFIG_FILE_PATH', '/export/home/dpower/jag/eta_master/scripts/py/monitor/status.json')
LOG_FILE = os.environ.get('LOG_FILE', '/export/home/dpower/project/log/pp_status_ws4.log')

# Configure the logger
Log.configure_logger(LOG_FILE)
logger = Log.get_logger()

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

# Define GraphQL schema
type_defs = gql("""
    type Query {
        processes: [ProcessDataGraphQL]
    }

    type ProcessDataGraphQL {
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
""")

# Define resolver functions
query = QueryType()

@query.field("processes")
def resolve_processes(_, info):
    return load_data()

# Create executable schema
schema = make_executable_schema(type_defs, query)

# Create FastAPI app
app = FastAPI()

# Include GraphQL route
graphql_server = GraphQL(schema)
app.add_route("/graphql", graphql_server)

# Define REST API endpoint
@app.get("/processes", response_model=List[ProcessData])
async def get_processes():
    try:
        return load_data()
    except Exception as e:
        logger.error(f"Error retrieving process data: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An error occurred while retrieving process data.")

# Define new REST API endpoint to return group, staging folder, and file_count
@app.get("/processes/summary", response_model=List[dict])
async def get_processes_summary():
    try:
        data = load_data()
        summary = [{"seq": item.sequence, "group": item.group, "staging_folder": item.staging_folder, "file_count": item.file_count, "status": item.status} for item in data]
        return summary
    except Exception as e:
        logger.error(f"Error retrieving process summary data: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An error occurred while retrieving process summary data.")

# Startup event handler
@app.on_event("startup")
async def startup_event():
    logger.info("Application started")

# Shutdown event handler
@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Application shutting down")

if __name__ == "__main__":
    uvicorn.run("pp_status_ws5:app", host="0.0.0.0", port=5500, reload=True)
