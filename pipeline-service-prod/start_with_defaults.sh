#!/bin/bash
# Quick start script for Pipeline Service with default Oracle credentials
# Usage: ./start_with_defaults.sh [DSN] [PORT]

DSN=${1:-exnqa-db.onsemi.com:1740/EXNQA.onsemi.com}
PORT=${2:-8001}

echo "=========================================="
echo "Pipeline Service - Quick Start"
echo "=========================================="
echo "Backend: Oracle"
echo "DSN: $DSN"
echo "User: refdb (default)"
echo "Port: $PORT"
echo "=========================================="
echo ""
echo "Starting service..."
echo "API docs will be available at: http://localhost:$PORT/docs"
echo ""

python run_with_args.py \
  --backend oracle \
  --oracle-dsn "$DSN" \
  --oracle-user \
  --port "$PORT" \
  --reload \
  --cors-allow-all
