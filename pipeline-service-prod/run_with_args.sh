#!/bin/bash
# Pipeline Service Runner with Command-Line Arguments
# Similar to run.sh but with enhanced CLI argument support and default credentials

set -e  # Exit on any error

# --- Python interpreter selection ---
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

# --- Defaults ---
DEFAULT_HOST="127.0.0.1"
DEFAULT_PORT="8001"
DEFAULT_BACKEND="oracle"
DEFAULT_JSONL_PATH="/apps/exensio_data/reference_data/benchmark/benchmark.jsonl"
DEFAULT_ORACLE_DSN="exnqa-db.onsemi.com:1740/EXNQA.onsemi.com"
DEFAULT_ORACLE_TABLE="pipeline_runs"
DEFAULT_CORS_ORIGINS="http://localhost:3000,http://localhost:5173,http://localhost:8080,http://usaz15ls088:8080"
DEFAULT_CORS_ALLOW_ALL="false"
DEFAULT_RELOAD="false"

# Default credentials (used when --oracle-user flag is present without value)
DEFAULT_ORACLE_USER="refdb"
DEFAULT_ORACLE_PASSWORD='br#^gox66312sdAB'

# Initialize from environment or defaults
HOST=${HOST:-$DEFAULT_HOST}
PORT=${PORT:-$DEFAULT_PORT}
PIPELINE_BACKEND=${PIPELINE_BACKEND:-$DEFAULT_BACKEND}
PIPELINE_JSONL_PATH=${PIPELINE_JSONL_PATH:-$DEFAULT_JSONL_PATH}
ORACLE_DSN=${ORACLE_DSN:-$DEFAULT_ORACLE_DSN}
ORACLE_USER=${ORACLE_USER:-}
ORACLE_PASSWORD=${ORACLE_PASSWORD:-}
ORACLE_TABLE=${ORACLE_TABLE:-$DEFAULT_ORACLE_TABLE}
CORS_ORIGINS=${CORS_ORIGINS:-$DEFAULT_CORS_ORIGINS}
CORS_ALLOW_ALL=${CORS_ALLOW_ALL:-$DEFAULT_CORS_ALLOW_ALL}
RELOAD=${RELOAD:-$DEFAULT_RELOAD}

# Flags to track if credentials were explicitly set via CLI
USE_DEFAULT_CREDENTIALS=false
ORACLE_USER_SET=false
ORACLE_PASSWORD_SET=false

# Colors for output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()  { echo -e "${RED}[ERROR]${NC} $1"; }
print_info()   { echo -e "${BLUE}[INFO]${NC} $1"; }

show_usage() {
  cat << 'EOF'
Usage: ./run_with_args.sh [OPTIONS]

Pipeline Service with Command-Line Arguments and Default Credentials

OPTIONS:
  Backend Selection:
    --backend {jsonl|oracle}    Storage backend (default: jsonl)

  JSONL Options:
    --jsonl-path PATH           Path to JSONL file

  Oracle Options:
    --oracle-dsn DSN            Oracle DSN (default: exnqa-db.onsemi.com:1740/EXNQA.onsemi.com)
    --oracle-user [USER]        Username (optional value; if omitted, uses default: refdb)
    --oracle-password [PASS]    Password (optional value; if omitted, uses default)
    --oracle-table TABLE        Table name (default: pipeline_runs)

  Server Options:
    --host HOST                 Host to bind (default: 127.0.0.1)
    -p, --port PORT             Port to bind (default: 8001)
    --reload                    Enable auto-reload for development
    --dev                       Alias for --reload

  CORS Options:
    --cors-origins ORIGINS      Comma-separated allowed origins
    --cors-allow-all            Allow all CORS origins (development only)

  Help:
    -h, --help                  Show this help message

EXAMPLES:
  # Use default Oracle credentials and DSN (simplest)
  ./run_with_args.sh --backend oracle --oracle-user

  # Use default credentials with custom DSN
  ./run_with_args.sh --backend oracle --oracle-dsn DWPRD --oracle-user

  # Custom Oracle credentials
  ./run_with_args.sh --backend oracle --oracle-dsn DWPRD \
    --oracle-user myuser --oracle-password mypass

  # JSONL backend
  ./run_with_args.sh --backend jsonl --jsonl-path ./data/pipeline.jsonl

  # Development mode with auto-reload
  ./run_with_args.sh --backend oracle --oracle-user --reload

  # Custom port and host
  ./run_with_args.sh --backend oracle --oracle-user --port 8080 --host 0.0.0.0

CREDENTIAL RESOLUTION:
  1. Command-line explicit values (highest priority)
  2. Environment variables (ORACLE_USER, ORACLE_PASSWORD)
  3. Default credentials (when --oracle-user flag present without value)
  4. Error (when no credentials available for Oracle backend)

DEFAULT CREDENTIALS:
  Username: refdb
  Password: br#^gox66312sdAB
  DSN:      exnqa-db.onsemi.com:1740/EXNQA.onsemi.com (QA database)

ENVIRONMENT VARIABLES:
  PYTHON_BIN, HOST, PORT, PIPELINE_BACKEND, PIPELINE_JSONL_PATH
  ORACLE_DSN, ORACLE_USER, ORACLE_PASSWORD, ORACLE_TABLE
  CORS_ORIGINS, CORS_ALLOW_ALL, RELOAD

COMPARISON WITH PERL SCRIPT:
  Perl:   --benchmark_db_user     Python: --oracle-user
  Perl:   --benchmark_db_pass     Python: --oracle-password
  Perl:   --benchmark_db_dsn      Python: --oracle-dsn

EOF
}

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

resolve_oracle_credentials() {
  if [ "$PIPELINE_BACKEND" != "oracle" ]; then
    return 0
  fi

  print_status "Resolving Oracle credentials..."

  # If --oracle-user flag was passed without value, use defaults
  if [ "$USE_DEFAULT_CREDENTIALS" = true ]; then
    ORACLE_USER="$DEFAULT_ORACLE_USER"
    ORACLE_PASSWORD="$DEFAULT_ORACLE_PASSWORD"
    print_info "Using default Oracle credentials (user: $ORACLE_USER)"
    return 0
  fi

  # Check if credentials are set (from CLI or env vars)
  if [ -z "$ORACLE_USER" ] || [ -z "$ORACLE_PASSWORD" ]; then
    print_error "Oracle backend selected but credentials not provided!"
    echo ""
    echo "Options:"
    echo "  1. Use default credentials:"
    echo "     ./run_with_args.sh --backend oracle --oracle-user"
    echo ""
    echo "  2. Provide custom credentials:"
    echo "     ./run_with_args.sh --backend oracle --oracle-user myuser --oracle-password mypass"
    echo ""
    echo "  3. Use environment variables:"
    echo "     export ORACLE_USER=myuser"
    echo "     export ORACLE_PASSWORD=mypass"
    echo "     ./run_with_args.sh --backend oracle"
    echo ""
    exit 1
  fi

  print_status "Oracle credentials validated ✓"
}

start_app() {
  print_status "Starting Pipeline Service..."
  print_status "Configuration:"
  echo "  Backend: $PIPELINE_BACKEND"
  echo "  Host: $HOST"
  echo "  Port: $PORT"
  echo "  CORS Origins: $CORS_ORIGINS"
  echo "  CORS Allow All: $CORS_ALLOW_ALL"
  echo "  Reload: $RELOAD"
  
  if [ "$PIPELINE_BACKEND" = "jsonl" ]; then
    echo "  JSONL Path: $PIPELINE_JSONL_PATH"
  else
    echo "  Oracle DSN: $ORACLE_DSN"
    echo "  Oracle User: $ORACLE_USER"
    echo "  Oracle Table: $ORACLE_TABLE"
  fi
  
  echo ""
  print_status "API URLs:"
  echo "  Docs:   http://$HOST:$PORT/docs"
  echo "  Health: http://$HOST:$PORT/health"
  echo "  API:    http://$HOST:$PORT/get_pipeline_info"
  echo ""
  
  if [ "$HOST" = "127.0.0.1" ]; then
    print_info "External access via NGINX proxy:"
    echo "  Docs:      http://usaz15ls088:8080/pipeline-service/docs"
    echo "  Dashboard: http://usaz15ls088:8080/pipeline-dashboard/"
    echo ""
  fi
  
  print_status "Starting server..."

  # Export environment variables
  export PIPELINE_BACKEND PIPELINE_JSONL_PATH
  export ORACLE_DSN ORACLE_USER ORACLE_PASSWORD ORACLE_TABLE
  export CORS_ORIGINS CORS_ALLOW_ALL PYTHONUNBUFFERED=1

  # Build uvicorn args
  UVICORN_ARGS=(main:main_app --host "$HOST" --port "$PORT")
  
  if [ "$RELOAD" = "true" ] || [ "$RELOAD" = "1" ] || [ "$RELOAD" = "yes" ]; then
    UVICORN_ARGS+=(--reload)
  fi

  # Behind NGINX: respect X-Forwarded-* headers
  UVICORN_ARGS+=(--proxy-headers)
  UVICORN_ARGS+=(--forwarded-allow-ips 127.0.0.1)

  # Start using the selected Python interpreter
  exec "$PYTHON_BIN" -m uvicorn "${UVICORN_ARGS[@]}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_usage
      exit 0
      ;;
    --backend)
      PIPELINE_BACKEND="$2"
      shift 2
      ;;
    --jsonl-path)
      PIPELINE_JSONL_PATH="$2"
      shift 2
      ;;
    --oracle-dsn)
      ORACLE_DSN="$2"
      shift 2
      ;;
    --oracle-user)
      if [ -n "${2:-}" ] && [[ ! "$2" =~ ^-- ]]; then
        # Value provided
        ORACLE_USER="$2"
        ORACLE_USER_SET=true
        shift 2
      else
        # No value provided, use defaults
        USE_DEFAULT_CREDENTIALS=true
        shift 1
      fi
      ;;
    --oracle-password)
      if [ -n "${2:-}" ] && [[ ! "$2" =~ ^-- ]]; then
        # Value provided
        ORACLE_PASSWORD="$2"
        ORACLE_PASSWORD_SET=true
        shift 2
      else
        # No value provided, will use default if --oracle-user also triggered defaults
        shift 1
      fi
      ;;
    --oracle-table)
      ORACLE_TABLE="$2"
      shift 2
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    --reload)
      RELOAD="true"
      shift 1
      ;;
    --dev)
      RELOAD="true"
      shift 1
      ;;
    --cors-origins)
      CORS_ORIGINS="$2"
      shift 2
      ;;
    --cors-allow-all)
      CORS_ALLOW_ALL="true"
      shift 1
      ;;
    *)
      print_error "Unknown option: $1"
      echo ""
      show_usage
      exit 1
      ;;
  esac
done

main() {
  print_status "Pipeline Service Startup Script"
  print_status "Enhanced with CLI arguments and default credentials"
  echo ""
  check_dependencies
  check_python_packages
  resolve_oracle_credentials
  start_app
}

main "$@"
