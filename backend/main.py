"""
vCRGlove Research Backend
=========================
Receives MovementSessions from the iPhone app, stores them in a SQLite
database, and exposes a REST API for the Streamlit dashboard.

Endpoints:
  POST /sessions          — receive one session from the app
  GET  /sessions          — list all sessions (with optional ?patient_id= filter)
  GET  /sessions/{id}     — single session by UUID
  GET  /export/metrics    — flat CSV of all trial metrics (clinic download)
  GET  /health            — liveness probe

Run locally:
  pip install fastapi uvicorn[standard] sqlalchemy pydantic
  uvicorn main:app --reload --host 0.0.0.0 --port 8000

For production (UKE server) use the provided docker-compose.yml.
"""

import os
import csv
import io
import json
import hashlib
import secrets
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException, Depends, Header, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import (
    create_engine, Column, String, Integer, Float, DateTime, Text
)
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

# ── Configuration ─────────────────────────────────────────────────────────────

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./vcrglove.db")
API_KEY      = os.getenv("VCR_API_KEY", "REPLACE_WITH_UKE_API_KEY")

# ── Database ──────────────────────────────────────────────────────────────────

engine       = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

class Base(DeclarativeBase): pass

class TrialRow(Base):
    __tablename__ = "trials"

    trial_id                  = Column(String, primary_key=True)
    session_id                = Column(String, index=True)
    patient_id                = Column(String, index=True)
    session_date              = Column(DateTime)
    context                   = Column(String)
    task                      = Column(String)
    side                      = Column(String)
    source                    = Column(String)
    stop_mode                 = Column(String)
    started_at                = Column(DateTime)
    duration_sec              = Column(Float)
    sample_count              = Column(Integer)
    cycle_count               = Column(Integer)
    frequency_hz              = Column(Float)
    mean_amplitude            = Column(Float)
    amplitude_decrement_slope = Column(Float)
    rhythm_cv                 = Column(Float)
    pause_count               = Column(Integer)
    onset_latency_sec         = Column(Float)
    quality_index             = Column(Float)
    raw_json                  = Column(Text)   # full session JSON for re-analysis

Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ── Pydantic models (mirrors MovementModels.swift) ────────────────────────────

class TimestampedSample(BaseModel):
    t: float
    value: float

class MovementMetrics(BaseModel):
    cycleCount: int
    frequencyHz: float
    meanAmplitude: float
    amplitudeDecrementSlope: float
    rhythmCV: float
    pauseCount: int
    onsetLatencySec: float
    qualityIndex: float

class StopCondition(BaseModel):
    mode: str
    targetReps: int
    targetDuration: float

class Trial(BaseModel):
    id: str
    taskType: str
    side: str
    source: str
    stopCondition: StopCondition
    startedAt: datetime
    startUptime: Optional[float] = None
    samples: list[TimestampedSample] = Field(default_factory=list)
    metrics: MovementMetrics

class MovementSession(BaseModel):
    id: str
    patientId: str
    date: datetime
    stimulationContext: str
    trials: list[Trial] = Field(default_factory=list)

# ── Auth ──────────────────────────────────────────────────────────────────────

def verify_api_key(authorization: str = Header(...)):
    token = authorization.removeprefix("Bearer ").strip()
    if not secrets.compare_digest(
        hashlib.sha256(token.encode()).digest(),
        hashlib.sha256(API_KEY.encode()).digest()
    ):
        raise HTTPException(status_code=401, detail="Invalid API key")

# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(title="vCRGlove Research Backend", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # tighten to dashboard origin in production
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"status": "ok", "ts": datetime.utcnow().isoformat()}

@app.post("/sessions", status_code=201, dependencies=[Depends(verify_api_key)])
def receive_session(session: MovementSession, db: Session = Depends(get_db)):
    raw = session.model_dump_json()
    for trial in session.trials:
        existing = db.get(TrialRow, trial.id)
        if existing:
            continue   # idempotent: ignore duplicate uploads
        duration = trial.samples[-1].t if trial.samples else 0.0
        row = TrialRow(
            trial_id                  = trial.id,
            session_id                = session.id,
            patient_id                = session.patientId,
            session_date              = session.date,
            context                   = session.stimulationContext,
            task                      = trial.taskType,
            side                      = trial.side,
            source                    = trial.source,
            stop_mode                 = trial.stopCondition.mode,
            started_at                = trial.startedAt,
            duration_sec              = duration,
            sample_count              = len(trial.samples),
            cycle_count               = trial.metrics.cycleCount,
            frequency_hz              = trial.metrics.frequencyHz,
            mean_amplitude            = trial.metrics.meanAmplitude,
            amplitude_decrement_slope = trial.metrics.amplitudeDecrementSlope,
            rhythm_cv                 = trial.metrics.rhythmCV,
            pause_count               = trial.metrics.pauseCount,
            onset_latency_sec         = trial.metrics.onsetLatencySec,
            quality_index             = trial.metrics.qualityIndex,
            raw_json                  = raw,
        )
        db.add(row)
    db.commit()
    return {"received": len(session.trials), "session_id": session.id}

@app.get("/sessions", dependencies=[Depends(verify_api_key)])
def list_sessions(patient_id: Optional[str] = None, db: Session = Depends(get_db)):
    q = db.query(TrialRow)
    if patient_id:
        q = q.filter(TrialRow.patient_id == patient_id)
    rows = q.order_by(TrialRow.session_date.desc()).all()
    return [_row_to_dict(r) for r in rows]

@app.get("/sessions/{session_id}", dependencies=[Depends(verify_api_key)])
def get_session(session_id: str, db: Session = Depends(get_db)):
    rows = db.query(TrialRow).filter(TrialRow.session_id == session_id).all()
    if not rows:
        raise HTTPException(status_code=404, detail="Session not found")
    return [_row_to_dict(r) for r in rows]

@app.get("/export/metrics", dependencies=[Depends(verify_api_key)])
def export_metrics_csv(patient_id: Optional[str] = None,
                       db: Session = Depends(get_db)):
    q = db.query(TrialRow)
    if patient_id:
        q = q.filter(TrialRow.patient_id == patient_id)
    rows = q.order_by(TrialRow.session_date.asc()).all()

    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=[
        "session_id","patient_id","session_date","context",
        "trial_id","task","side","source","stop_mode","started_at",
        "duration_sec","sample_count","cycle_count","frequency_hz",
        "mean_amplitude","amplitude_decrement_slope","rhythm_cv",
        "pause_count","onset_latency_sec","quality_index",
    ])
    writer.writeheader()
    for r in rows:
        writer.writerow(_row_to_dict(r))

    return Response(
        content=buf.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=metrics.csv"}
    )

def _row_to_dict(r: TrialRow) -> dict:
    return {
        "session_id":                r.session_id,
        "patient_id":                r.patient_id,
        "session_date":              r.session_date.isoformat() if r.session_date else "",
        "context":                   r.context,
        "trial_id":                  r.trial_id,
        "task":                      r.task,
        "side":                      r.side,
        "source":                    r.source,
        "stop_mode":                 r.stop_mode,
        "started_at":                r.started_at.isoformat() if r.started_at else "",
        "duration_sec":              r.duration_sec,
        "sample_count":              r.sample_count,
        "cycle_count":               r.cycle_count,
        "frequency_hz":              r.frequency_hz,
        "mean_amplitude":            r.mean_amplitude,
        "amplitude_decrement_slope": r.amplitude_decrement_slope,
        "rhythm_cv":                 r.rhythm_cv,
        "pause_count":               r.pause_count,
        "onset_latency_sec":         r.onset_latency_sec,
        "quality_index":             r.quality_index,
    }
