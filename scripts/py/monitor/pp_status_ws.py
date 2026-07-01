import os
from typing import List, Optional
from fastapi import FastAPI
from pydantic import BaseModel
import json
import uvicorn

app = FastAPI()

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

def load_data():
    file_path = "/export/home/dpower/jag/eta_master/scripts/py/monitor/status.json"
    if not os.path.exists(file_path):
        raise ValueError(f"File not found: {file_path}")

    with open(file_path, "r") as file:
        data = json.load(file)
    return [ProcessData(**{k: v if v is not None else 0 for k, v in item.items()}) for item in data]

@app.get("/processes", response_model=List[ProcessData])
async def get_processes():
    return load_data()

if __name__ == "__main__":
    uvicorn.run("pp_status_ws:app", host="0.0.0.0", port=5500, reload=True)