#!/usr/bin/env bash
# Start FastAPI server with auto-reload
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
