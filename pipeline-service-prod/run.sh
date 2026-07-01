#!/bin/bash
# Pipeline Info API Runner Script (NGINX-ready)
# FastAPI application that works behind NGINX proxy at /pipeline-service/

set -e  # Exit on any error

# --- Python interpreter selection ---
# Prefer explicit env, then your 3.13 path, then python3/python fallback.
if [ -n "${PYTHON_BIN:-}" ]; then
  :
elif [ -x /export/home/dpower/python-3.13.5/bin/python3.13 ]; then
  PYTHON_BIN="/export/home/dpower/python-3.13.5/bin/python3.13"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
else
  echo "[ERROR] No suitable Python found (expected /export/home/dpower/python-3.13.5/bin/python3.13 or python3 in PATH)" >&2
  exit 1
fi

# --- Defaults (can be overridden via env or CLI) ---
DEFAULT_HOST="127.0.0.1"  # Bind FastAPI to localhost for NGINX proxy
DEFAULT_PORT="8001"       # Matches NGINX upstream pipeline-service port
DEFAULT_BACKEND="oracle"
DEFAULT_JSONL_PATH="/apps/exensio_data/reference_data/benchmark/benchmark.jsonl"
DEFAULT_CORS_ORIGINS="http://localhost:3000,http://localhost:5173,http://localhost:8080,http://usaz15ls088:8080"
DEFAULT_CORS_ALLOW_ALL="false"

# Get configuration from environment or use defaults
HOST=${HOST:-$DEFAULT_HOST}
PORT=${PORT:-$DEFAULT_PORT}
PIPELINE_BACKEND=${PIPELINE_BACKEND:-$DEFAULT_BACKEND}
PIPELINE_JSONL_PATH=${PIPELINE_JSONL_PATH:-$DEFAULT_JSONL_PATH}
CORS_ORIGINS=${CORS_ORIGINS:-$DEFAULT_CORS_ORIGINS}
CORS_ALLOW_ALL=${CORS_ALLOW_ALL:-$DEFAULT_CORS_ALLOW_ALL}
RELOAD=${RELOAD:-false}     # Default to no reload for service use

# Colors for output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()  { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
  print_status "Checking dependencies..."
  for file in "main.py" "app/models.py" "app/repository.py"; do
    if [ ! -f "$file" ]; then
      print_error "Required file $file not found!"
      exit 1
    fi
  done
  if [ "$PIPELINE_BACKEND" = "jsonl" ]; then
    if [ ! -f "$PIPELINE_JSONL_PATH" ]; then
      print_warning "JSONL file $PIPELINE_JSONL_PATH not found. Will create sample data."
      create_sample_data
    fi
  fi
  print_status "Dependencies check passed ✓"
}

create_sample_data() {
  print_status "Creating sample pipeline data..."
  mkdir -p "$(dirname "$PIPELINE_JSONL_PATH")"
  cat > "$PIPELINE_JSONL_PATH" << 'EOF'
{"start_local": "2025-08-08 05:07:01", "end_local": "2025-08-08 05:29:07", "start_utc": "2025-08-08T12:07:01Z", "end_utc": "2025-08-08T12:29:07Z", "elapsed_seconds": 1325.571, "elapsed_human": "22m 5s", "output_file": "/apps/data/pipeline/sales_etl/output-20250808_050701.data", "rowcount": 4342, "log_file": "/apps/data/pipeline/logs/sales_etl-20250808_050701.log", "pid": 38298, "date_code": "20250808_050701", "pipeline_name": "sales_etl", "script_name": "process_sales_data.py", "pipeline_type": "batch", "environment": "prod"}
{"start_local": "2025-08-08 06:07:01", "end_local": "2025-08-08 06:29:25", "start_utc": "2025-08-08T13:07:01Z", "end_utc": "2025-08-08T13:29:25Z", "elapsed_seconds": 1343.854, "elapsed_human": "22m 23s", "output_file": "/apps/data/pipeline/user_analytics/output-20250808_060701.data", "rowcount": 4387, "log_file": "/apps/data/pipeline/logs/user_analytics-20250808_060701.log", "pid": 117881, "date_code": "20250808_060701", "pipeline_name": "user_analytics", "script_name": "analyze_user_behavior.py", "pipeline_type": "batch", "environment": "prod"}
{"start_local": "2025-08-08 07:07:01", "end_local": "2025-08-08 07:28:15", "start_utc": "2025-08-08T14:07:01Z", "end_utc": "2025-08-08T14:28:15Z", "elapsed_seconds": 1274.123, "elapsed_human": "21m 14s", "output_file": "/apps/data/pipeline/ml_training/output-20250808_070701.data", "rowcount": 4156, "log_file": "/apps/data/pipeline/logs/ml_training-20250808_070701.log", "pid": 125432, "date_code": "20250808_070701", "pipeline_name": "ml_training", "script_name": "train_recommendation_model.py", "pipeline_type": "ml", "environment": "prod"}
EOF
  print_status "Sample data created at $PIPELINE_JSONL_PATH"
}

check_python_packages() {
  print_status "Checking Python packages using: $PYTHON_BIN"
  "$PYTHON_BIN" -c "import fastapi, uvicorn, pydantic" 2>/dev/null || {
    print_error "Required Python packages not found!"
    print_status "Install with: ${PYTHON_BIN%/python*}/pip install fastapi uvicorn pydantic"
    exit 1
  }
  if [ "$PIPELINE_BACKEND" = "oracle" ]; then
    "$PYTHON_BIN" -c "import oracledb" 2>/dev/null || {
      print_error "python-oracledb package not found (required for Oracle backend)!"
      print_status "Install with: ${PYTHON_BIN%/python*}/pip install python-oracledb"
      exit 1
    }
  fi
  print_status "Python packages check passed ✓"
}

check_oracle_config() {
  if [ "$PIPELINE_BACKEND" = "oracle" ]; then
    print_status "Validating Oracle configuration..."
    if [ -z "$ORACLE_DSN" ] || [ -z "$ORACLE_USER" ] || [ -z "$ORACLE_PASSWORD" ]; then
      print_error "Oracle backend selected but missing configuration!"
      echo "Required environment variables:"
      echo "  ORACLE_DSN=host:port/service"
      echo "  ORACLE_USER=username"
      echo "  ORACLE_PASSWORD=password"
      echo "  ORACLE_TABLE=table_name (optional, defaults to PIPELINE_RUNS)"
      exit 1
    fi
    print_status "Oracle configuration validated ✓"
  fi
}

start_app() {
  print_status "Starting Pipeline Info API..."
  print_status "Configuration:"
  echo "  Backend: $PIPELINE_BACKEND"
  echo "  Host: $HOST"
  echo "  Port: $PORT"
  echo "  CORS Origins: $CORS_ORIGINS"
  echo "  CORS Allow All: $CORS_ALLOW_ALL"
  if [ "$PIPELINE_BACKEND" = "jsonl" ]; then
    echo "  JSONL Path: $PIPELINE_JSONL_PATH"
  else
    echo "  Oracle DSN: $ORACLE_DSN"
    echo "  Oracle User: $ORACLE_USER"
    echo "  Oracle Table: ${ORACLE_TABLE:-PIPELINE_RUNS}"
  fi
  echo ""
  print_status "Internal API URLs (FastAPI direct access):"
  echo "  Docs: http://$HOST:$PORT/docs"
  echo "  Health: http://$HOST:$PORT/health"
  echo "  API: http://$HOST:$PORT/get_pipeline_info"
  echo ""
  print_status "External URLs (via NGINX proxy on port 8080):"
  echo "  Docs: http://usaz15ls088:8080/pipeline-service/docs"
  echo "  Health: http://usaz15ls088:8080/pipeline-service/health"
  echo "  API: http://usaz15ls088:8080/pipeline-service/get_pipeline_info"
  echo "  Dashboard: http://usaz15ls088:8080/pipeline-dashboard/"
  echo ""
  print_status "Starting server..."

  export PIPELINE_BACKEND PIPELINE_JSONL_PATH ORACLE_DSN ORACLE_USER ORACLE_PASSWORD ORACLE_TABLE
  export CORS_ORIGINS CORS_ALLOW_ALL PYTHONUNBUFFERED=1

  # Build uvicorn args
  UVICORN_ARGS=(main:main_app --host "$HOST" --port "$PORT")
  case "${RELOAD,,}" in
    true|1|yes) UVICORN_ARGS+=(--reload);;
  esac

  # Behind NGINX: respect X-Forwarded-* and only trust localhost proxy
  UVICORN_ARGS+=(--proxy-headers)
  UVICORN_ARGS+=(--forwarded-allow-ips 127.0.0.1)

  # Do NOT set --root-path; app is mounted at /pipeline-service in code.
  # If you ever remove the mount and want NGINX to preserve the prefix,
  # you could then add: UVICORN_ARGS+=(--root-path /pipeline-service)

  # Start using the selected Python interpreter
  exec "$PYTHON_BIN" -m uvicorn "${UVICORN_ARGS[@]}"
}

show_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Pipeline Info API Runner Script (NGINX-ready)"
  echo "FastAPI application that works behind NGINX proxy at /pipeline-service/"
  echo ""
  echo "Options:"
  echo "  -h, --help          Show this help message"
  echo "  -p, --port          Port to run on (default: 8001)"
  echo "  --host              Host to bind to (default: 127.0.0.1)"
  echo "  --backend           Backend type: jsonl|oracle (default: jsonl)"
  echo "  --jsonl-path        Path to JSONL file"
  echo "  --cors-origins      Comma-separated CORS origins"
  echo "  --cors-allow-all    Allow all CORS origins (true/false, default: false)"
  echo "  --reload            Enable autoreload (true/false, default: false)"
  echo "  --dev               Alias for --reload true"
  echo ""
  echo "Environment Variables:"
  echo "  PYTHON_BIN            Absolute python path (default: /export/home/dpower/python-3.13.5/bin/python3.13)"
  echo "  HOST, PORT, PIPELINE_BACKEND, PIPELINE_JSONL_PATH, ORACLE_*"
  echo "  CORS_ORIGINS, CORS_ALLOW_ALL, RELOAD"
  echo ""
  echo "Examples:"
  echo "  $0                                  # Run with defaults (localhost:8001, no reload)"
  echo "  RELOAD=true $0                      # Enable reload"
  echo "  $0 --backend oracle                 # Use Oracle backend"
  echo "  $0 -p 9000 --host 127.0.0.1         # Custom bind"
  echo ""
  echo "With NGINX proxy, access via:"
  echo "  http://usaz15ls088:8080/pipeline-service/docs"
  echo "  http://usaz15ls088:8080/pipeline-service/health"
  echo "  http://usaz15ls088:8080/pipeline-dashboard/"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help) show_usage; exit 0;;
    -p|--port) PORT="$2"; shift 2;;
    --host) HOST="$2"; shift 2;;
    --backend) PIPELINE_BACKEND="$2"; shift 2;;
    --jsonl-path) PIPELINE_JSONL_PATH="$2"; shift 2;;
    --cors-origins) CORS_ORIGINS="$2"; shift 2;;
    --cors-allow-all) CORS_ALLOW_ALL="$2"; shift 2;;
    --reload) RELOAD="$2"; shift 2;;
    --dev) RELOAD="true"; shift 1;;
    *) print_error "Unknown option: $1"; show_usage; exit 1;;
  esac
done

main() {
  print_status "Pipeline Info API Startup Script (NGINX-ready)"
  print_status "Created by: JA Garcia"
  print_status "Date: 2025-09-02"
  print_status "This script configures FastAPI to work behind NGINX proxy"
  echo ""
  check_dependencies
  check_python_packages
  check_oracle_config
  start_app
}
main "$@"