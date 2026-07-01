📦 JND Lot Metadata Service
🧭 Synopsis
A FastAPI-based microservice that extracts metadata from JND .lot files. It returns the technology, lot type, and TPNO for a given lot ID, along with a custom status and error message.

📄 Description
This service reads .lot files from a specified directory and extracts metadata from the last line of the file. It is designed to support automated systems that rely on structured JND lot metadata.

🔍 What It Does:
Identifies the .lot file using the prefix of the provided lot ID.
Reads the last line of the file.
Extracts:
Technology (column 17)
Lot Type (column 24)
TPNO (column 2)
Returns a structured JSON response with:
status: Custom status code (LOT_METADATA, NO_JND_LOT_METADATA_FILE, UNKNOWN)
errorMessage: null if successful, or a descriptive error message
⚙️ Installation
# 1. Clone the repository
git clone https://code.onsemi.com/scm/exensio/eta.git .
cd jnd-lot-metadata-service

# 2. Create and activate a virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Set environment variables
# Create a .env file or export LOT_FILES_DIR in your shell


🚀 Usage
Run the FastAPI server:

uvicorn app.main:app --reload

Access the interactive API docs at:
http://localhost:8000/docs

🔌 API Endpoint
GET /jnd-lot-metadata/lotid/{lot}
🔸 Query Parameters:
lot (required): Lot ID to search for (e.g., SY46638.1)
✅ Successful Response:
{
  "status": "LOT_METADATA",
  "errorMessage": null,
  "lot": "SY46638.1",
  "tpno": "FNP7",
  "technology": "T8-MV",
  "lot_type": "PS"
}

❌ Error Responses:
HTTP Code	status	Description
404	NO_JND_LOT_METADATA_FILE	File not found
422	UNKNOWN	Insufficient data in the file
500	UNKNOWN	Unexpected or CSV parsing error
👤 Author
Juniffer Allan Garcia
📧 junifferallan.garcia@onsemi.com

📜 License
(C) onsemi 2025. All rights reserved.