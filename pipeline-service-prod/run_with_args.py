#!/usr/bin/env python3
"""
Pipeline Service Runner Script with Command-Line Arguments (NGINX-ready)

Supports default Oracle credentials similar to getCamstarWafer2AssemblyGenealogy.pl:
- If --oracle-user is passed without a value, uses default credentials (refdb/br#^gox66312sdAB)
- Command-line args override environment variables
- Backward compatible with environment variable configuration
- Works behind NGINX proxy at /pipeline-service/

Created by: JA Garcia
Date: 2025-09-02 (Enhanced with run.sh features)

Usage:
    # Use default credentials (simplest)
    python run_with_args.py --backend oracle --oracle-user
    
    # Custom credentials via command line
    python run_with_args.py --backend oracle --oracle-dsn DWPRD --oracle-user myuser --oracle-password mypass
    
    # Use environment variables (existing behavior)
    export ORACLE_USER=myuser
    export ORACLE_PASSWORD=mypass
    python run_with_args.py --backend oracle --oracle-dsn DWPRD
    
    # JSONL backend (default)
    python run_with_args.py --backend jsonl --jsonl-path ./data/pipeline.jsonl
    
    # Development mode with auto-reload
    python run_with_args.py --backend oracle --oracle-user --reload
"""

import argparse
import os
import sys
import uvicorn
from pathlib import Path


# ANSI color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color


def print_status(msg):
    """Print info message in green"""
    print(f"{Colors.GREEN}[INFO]{Colors.NC} {msg}")


def print_warning(msg):
    """Print warning message in yellow"""
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {msg}")


def print_error(msg):
    """Print error message in red"""
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}", file=sys.stderr)


def check_dependencies():
    """Check that required files exist"""
    print_status("Checking dependencies...")
    required_files = ["main.py", "app/models.py", "app/repository.py"]
    
    for file in required_files:
        if not Path(file).exists():
            print_error(f"Required file {file} not found!")
            sys.exit(1)
    
    print_status("Dependencies check passed ✓")


def check_python_packages(backend):
    """Check that required Python packages are installed"""
    print_status("Checking Python packages...")
    
    try:
        import fastapi
        import pydantic
        # uvicorn is already imported at top
    except ImportError as e:
        print_error(f"Required Python packages not found: {e}")
        print_status("Install with: pip install fastapi uvicorn pydantic")
        sys.exit(1)
    
    if backend == "oracle":
        try:
            import oracledb
        except ImportError:
            print_error("python-oracledb package not found (required for Oracle backend)!")
            print_status("Install with: pip install python-oracledb")
            sys.exit(1)
    
    print_status("Python packages check passed ✓")


def create_sample_data(jsonl_path):
    """Create sample JSONL data if file doesn't exist"""
    print_status("Creating sample pipeline data...")
    
    # Ensure parent directory exists
    Path(jsonl_path).parent.mkdir(parents=True, exist_ok=True)
    
    sample_data = [
        '{"start_local": "2025-08-08 05:07:01", "end_local": "2025-08-08 05:29:07", "start_utc": "2025-08-08T12:07:01Z", "end_utc": "2025-08-08T12:29:07Z", "elapsed_seconds": 1325.571, "elapsed_human": "22m 5s", "output_file": "/apps/data/pipeline/sales_etl/output-20250808_050701.data", "rowcount": 4342, "log_file": "/apps/data/pipeline/logs/sales_etl-20250808_050701.log", "pid": 38298, "date_code": "20250808_050701", "pipeline_name": "sales_etl", "script_name": "process_sales_data.py", "pipeline_type": "batch", "environment": "prod", "metadata": {}, "benchmark": {}}',
        '{"start_local": "2025-08-08 06:07:01", "end_local": "2025-08-08 06:29:25", "start_utc": "2025-08-08T13:07:01Z", "end_utc": "2025-08-08T13:29:25Z", "elapsed_seconds": 1343.854, "elapsed_human": "22m 23s", "output_file": "/apps/data/pipeline/user_analytics/output-20250808_060701.data", "rowcount": 4387, "log_file": "/apps/data/pipeline/logs/user_analytics-20250808_060701.log", "pid": 117881, "date_code": "20250808_060701", "pipeline_name": "user_analytics", "script_name": "analyze_user_behavior.py", "pipeline_type": "batch", "environment": "prod", "metadata": {}, "benchmark": {}}',
        '{"start_local": "2025-08-08 07:07:01", "end_local": "2025-08-08 07:28:15", "start_utc": "2025-08-08T14:07:01Z", "end_utc": "2025-08-08T14:28:15Z", "elapsed_seconds": 1274.123, "elapsed_human": "21m 14s", "output_file": "/apps/data/pipeline/ml_training/output-20250808_070701.data", "rowcount": 4156, "log_file": "/apps/data/pipeline/logs/ml_training-20250808_070701.log", "pid": 125432, "date_code": "20250808_070701", "pipeline_name": "ml_training", "script_name": "train_recommendation_model.py", "pipeline_type": "ml", "environment": "prod", "metadata": {}, "benchmark": {}}'
    ]
    
    with open(jsonl_path, 'w') as f:
        f.write('\n'.join(sample_data) + '\n')
    
    print_status(f"Sample data created at {jsonl_path}")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Pipeline Service API with configurable backend and credentials (NGINX-ready)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Use default Oracle credentials and DSN (simplest)
  python run_with_args.py --backend oracle --oracle-user

  # Use default Oracle credentials with custom DSN
  python run_with_args.py --backend oracle --oracle-dsn DWPRD --oracle-user

  # Custom Oracle credentials
  python run_with_args.py --backend oracle --oracle-dsn DWPRD --oracle-user myuser --oracle-password mypass

  # JSONL backend
  python run_with_args.py --backend jsonl --jsonl-path ./data/pipeline.jsonl

  # Development mode with auto-reload
  python run_with_args.py --backend oracle --oracle-user --reload

  # Custom port and host
  python run_with_args.py --backend oracle --oracle-user --port 8080 --host 0.0.0.0

Note: If --oracle-user is specified without a value, default credentials will be used (user: refdb)
      Default DSN: exnqa-db.onsemi.com:1740/EXNQA.onsemi.com (QA database)

With NGINX proxy, access via:
  http://usaz15ls088:8080/pipeline-service/docs
  http://usaz15ls088:8080/pipeline-service/health
  http://usaz15ls088:8080/pipeline-dashboard/
        """
    )
    
    # Backend selection
    parser.add_argument(
        "--backend",
        choices=["jsonl", "oracle"],
        default=os.environ.get("PIPELINE_BACKEND", "oracle"),
        help="Storage backend (default: oracle or PIPELINE_BACKEND env var)"
    )
    
    # JSONL options
    parser.add_argument(
        "--jsonl-path",
        default=os.environ.get("PIPELINE_JSONL_PATH", "/apps/exensio_data/reference_data/benchmark/benchmark.jsonl"),
        help="Path to JSONL file (default: /apps/exensio_data/reference_data/benchmark/benchmark.jsonl or PIPELINE_JSONL_PATH env var)"
    )
    
    # Oracle options
    parser.add_argument(
        "--oracle-dsn",
        default=os.environ.get("ORACLE_DSN", "exnqa-db.onsemi.com:1740/EXNQA.onsemi.com"),
        help="Oracle DSN (TNS name or connection string, default: exnqa-db.onsemi.com:1740/EXNQA.onsemi.com)"
    )
    
    parser.add_argument(
        "--oracle-user",
        nargs="?",  # Optional value - allows flag without value for default credentials
        const="",   # Value when flag is present but no value provided
        default=None,  # Value when flag is not present at all
        help="Oracle username (if specified without value, uses default: refdb)"
    )
    
    parser.add_argument(
        "--oracle-password",
        nargs="?",  # Optional value
        const="",
        default=None,
        help="Oracle password (if specified without value, uses default)"
    )
    
    parser.add_argument(
        "--oracle-table",
        default=os.environ.get("ORACLE_TABLE", "pipeline_runs"),
        help="Oracle table name (default: pipeline_runs or ORACLE_TABLE env var)"
    )
    
    parser.add_argument(
        "--oracle-column-map",
        default=os.environ.get("ORACLE_COLUMN_MAP"),
        help="JSON mapping of model fields to DB columns"
    )
    
    # Server options
    parser.add_argument(
        "--host",
        default=os.environ.get("HOST", "127.0.0.1"),
        help="Host to bind to (default: 127.0.0.1 or HOST env var)"
    )
    
    parser.add_argument(
        "-p", "--port",
        type=int,
        default=int(os.environ.get("PORT", "8001")),
        help="Port to bind to (default: 8001 or PORT env var)"
    )
    
    parser.add_argument(
        "--reload",
        action="store_true",
        default=os.environ.get("RELOAD", "").lower() in ("true", "1", "yes"),
        help="Enable auto-reload for development"
    )
    
    parser.add_argument(
        "--dev",
        action="store_true",
        help="Alias for --reload (development mode)"
    )
    
    # CORS options
    parser.add_argument(
        "--cors-origins",
        default=os.environ.get("CORS_ORIGINS", "http://localhost:3000,http://localhost:5173,http://localhost:8080,http://usaz15ls088:8080"),
        help="Comma-separated list of allowed CORS origins"
    )
    
    parser.add_argument(
        "--cors-allow-all",
        action="store_true",
        default=os.environ.get("CORS_ALLOW_ALL", "").lower() in ("true", "1", "yes"),
        help="Allow all CORS origins (development only)"
    )
    
    return parser.parse_args()


def setup_environment(args):
    """Set environment variables based on command-line arguments."""
    
    # Handle --dev flag
    if args.dev:
        args.reload = True
    
    # Backend selection
    os.environ["PIPELINE_BACKEND"] = args.backend
    
    # JSONL configuration
    if args.backend == "jsonl":
        os.environ["PIPELINE_JSONL_PATH"] = args.jsonl_path
        
        # Check if JSONL file exists, create sample if not
        if not Path(args.jsonl_path).exists():
            print_warning(f"JSONL file {args.jsonl_path} not found. Creating sample data.")
            create_sample_data(args.jsonl_path)
        
        print_status(f"Using JSONL backend: {args.jsonl_path}")
    
    # Oracle configuration
    elif args.backend == "oracle":
        # DSN has a default, so it's always available
        os.environ["ORACLE_DSN"] = args.oracle_dsn
        
        # Credential resolution with default credentials support
        user = args.oracle_user
        password = args.oracle_password
        
        # Priority 1: Command-line explicit values
        if user is None:
            # Flag not provided, check environment variables
            user = os.environ.get("ORACLE_USER", "")
            password = os.environ.get("ORACLE_PASSWORD", "")
        
        # Priority 2: Default credentials (if flag present but empty)
        if args.oracle_user is not None and user == "":
            user = "refdb"
            password = "br#^gox66312sdAB"
            print_status(f"Using default Oracle credentials (user: {user})")
        
        # Validate credentials
        if not user or not password:
            print_error("Oracle credentials required. Use --oracle-user and --oracle-password,")
            print_error("        or pass --oracle-user without a value to use default credentials,")
            print_error("        or set ORACLE_USER and ORACLE_PASSWORD environment variables")
            sys.exit(1)
        
        os.environ["ORACLE_USER"] = user
        os.environ["ORACLE_PASSWORD"] = password
        os.environ["ORACLE_TABLE"] = args.oracle_table
        
        if args.oracle_column_map:
            os.environ["ORACLE_COLUMN_MAP"] = args.oracle_column_map
        
        print_status(f"Using Oracle backend: {args.oracle_dsn}")
        print_status(f"Oracle user: {user}")
        print_status(f"Oracle table: {args.oracle_table}")
    
    # CORS configuration
    os.environ["CORS_ORIGINS"] = args.cors_origins
    
    if args.cors_allow_all:
        os.environ["CORS_ALLOW_ALL"] = "true"
        print_warning("CORS allow all enabled (development only!)")
    else:
        os.environ["CORS_ALLOW_ALL"] = "false"
    
    # Ensure unbuffered output
    os.environ["PYTHONUNBUFFERED"] = "1"


def print_startup_info(args):
    """Print startup information and URLs"""
    print()
    print_status("=" * 70)
    print_status("Pipeline Service API Startup")
    print_status("Created by: JA Garcia")
    print_status("Date: 2025-09-02")
    print_status("This script configures FastAPI to work behind NGINX proxy")
    print_status("=" * 70)
    print()
    
    print_status("Configuration:")
    print(f"  Backend: {args.backend}")
    print(f"  Host: {args.host}")
    print(f"  Port: {args.port}")
    print(f"  Reload: {args.reload}")
    print(f"  CORS Origins: {args.cors_origins}")
    print(f"  CORS Allow All: {args.cors_allow_all}")
    
    if args.backend == "jsonl":
        print(f"  JSONL Path: {args.jsonl_path}")
    else:
        print(f"  Oracle DSN: {args.oracle_dsn}")
        print(f"  Oracle User: {os.environ.get('ORACLE_USER', 'N/A')}")
        print(f"  Oracle Table: {args.oracle_table}")
    
    print()
    print_status("Internal API URLs (FastAPI direct access):")
    print(f"  Docs:   http://{args.host}:{args.port}/docs")
    print(f"  Health: http://{args.host}:{args.port}/health")
    print(f"  API:    http://{args.host}:{args.port}/get_pipeline_info")
    
    print()
    print_status("External URLs (via NGINX proxy on port 8080):")
    print(f"  Docs:      http://usaz15ls088:8080/pipeline-service/docs")
    print(f"  Health:    http://usaz15ls088:8080/pipeline-service/health")
    print(f"  API:       http://usaz15ls088:8080/pipeline-service/get_pipeline_info")
    print(f"  Dashboard: http://usaz15ls088:8080/pipeline-dashboard/")
    
    print()
    print_status("Starting server...")
    print()


def main():
    args = parse_args()
    
    # Check dependencies
    check_dependencies()
    check_python_packages(args.backend)
    
    # Setup environment variables from command-line arguments
    setup_environment(args)
    
    # Print startup information
    print_startup_info(args)
    
    # Start uvicorn server with NGINX-ready configuration
    uvicorn.run(
        "main:main_app",
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level="info",
        proxy_headers=True,  # Respect X-Forwarded-* headers from NGINX
        forwarded_allow_ips="127.0.0.1"  # Only trust localhost proxy
    )


if __name__ == "__main__":
    main()
