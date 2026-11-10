import os
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import time

app = FastAPI()

# CORS: allow any origin
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In‑memory leaderboard (list of dicts)
leaderboard: list[dict] = []

# Server start time for uptime
_start_time = time.time()

class ScorePayload(BaseModel):
    player_name: str = Field(..., min_length=1, max_length=32)
    score: int = Field(..., ge=0)
    validation_hash: str = Field(..., min_length=1)

@app.get("/health")
async def health():
    uptime = int(time.time() - _start_time)
    return {
        "status": "ok",
        "uptime_seconds": uptime,
        "leaderboard_entries": len(leaderboard),
    }

@app.get("/api/v1/leaderboard")
async def get_leaderboard():
    # Return top 10 sorted by score descending
    top = sorted(leaderboard, key=lambda x: x["score"], reverse=True)[:10]
    return {"top": top}

@app.post("/api/v1/score")
async def submit_score(payload: ScorePayload):
    # Simple validation placeholder – in production replace with HMAC verification
    if not payload.validation_hash:
        raise HTTPException(status_code=400, detail="Invalid hash")
    entry = {"player_name": payload.player_name, "score": payload.score}
    leaderboard.append(entry)
    return {"detail": "Score recorded"}

