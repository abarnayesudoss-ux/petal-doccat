#!/usr/bin/env bash
# Production-style start (same command Render uses). PORT defaults to 8000 locally.
set -e
cd "$(dirname "$0")"
exec gunicorn backend.main:app -k uvicorn.workers.UvicornWorker \
  --bind "0.0.0.0:${PORT:-8000}" --workers 1 --timeout 180
