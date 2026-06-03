"""
Tally — FastAPI Backend Stub
============================
In-memory stub for the Tally data-collection platform.
All storage is in Python dicts; see TODO comments for production integration points.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

import tiktoken
from fastapi import FastAPI, Header, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Tally API",
    version="0.1.0",
    description="Stub backend for the Tally ethical data-collection platform.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# In-memory storage
# TODO: Replace with a real database (PostgreSQL / DynamoDB / etc.)
# ---------------------------------------------------------------------------

# { user_id: { "token_count": int, "balance": float, "lifetime_earnings": float } }
user_ledger: dict[str, dict] = {}

# { user_id: [ batch_dict, ... ] }
user_batches: dict[str, list[dict]] = {}

# { user_id: [ payout_dict, ... ] }
payout_history: dict[str, list[dict]] = {}

PAY_RATE = 0.0003  # USD per token

# ---------------------------------------------------------------------------
# Tiktoken encoder (loaded once)
# ---------------------------------------------------------------------------

enc = tiktoken.get_encoding("cl100k_base")

# ---------------------------------------------------------------------------
# Pydantic models — Requests
# ---------------------------------------------------------------------------


class AuthRequest(BaseModel):
    user_id: str


class IngestBatch(BaseModel):
    text: str
    app_context: Optional[str] = None
    wpm: Optional[float] = None
    backspace_rate: Optional[float] = None
    ts: str  # ISO-8601
    locale: str


class IngestRequest(BaseModel):
    user_id: str
    batches: list[IngestBatch]


class PayoutRequest(BaseModel):
    amount: Optional[float] = None


# ---------------------------------------------------------------------------
# Pydantic models — Responses
# ---------------------------------------------------------------------------


class AuthResponse(BaseModel):
    token: str
    user_id: str


class IngestResponse(BaseModel):
    accepted: int
    tokens_counted: int


class PayoutEntry(BaseModel):
    amount: float
    status: str
    requested_at: str


class EarningsResponse(BaseModel):
    token_count: int
    balance: float
    lifetime_earnings: float
    pay_rate: float = PAY_RATE
    payout_history: list[PayoutEntry]


class ExportResponse(BaseModel):
    user_id: str
    batches: list[dict]
    earnings: EarningsResponse
    exported_at: str


class DeleteResponse(BaseModel):
    deleted: bool
    message: str


class PayoutResponse(BaseModel):
    status: str
    amount: float
    payout_id: str


class HealthResponse(BaseModel):
    status: str
    version: str


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------


def _extract_user_id(authorization: str = Header(...)) -> str:
    """Extract user_id from a stub Bearer token of the form 'stub-token-{user_id}'."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    token = authorization[len("Bearer "):]
    prefix = "stub-token-"
    if not token.startswith(prefix):
        raise HTTPException(status_code=401, detail="Malformed stub token")
    user_id = token[len(prefix):]
    if user_id not in user_ledger:
        raise HTTPException(status_code=401, detail="Unknown user")
    return user_id


def _ensure_user(user_id: str) -> None:
    """Create a ledger entry for a user if one doesn't exist yet."""
    if user_id not in user_ledger:
        user_ledger[user_id] = {
            "token_count": 0,
            "balance": 0.0,
            "lifetime_earnings": 0.0,
        }
        user_batches[user_id] = []
        payout_history[user_id] = []


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.get("/", response_model=HealthResponse, tags=["health"])
async def health_check():
    """Root health-check endpoint."""
    return HealthResponse(status="ok", version=app.version)


# ---- Auth -----------------------------------------------------------------


@app.post("/auth/token", response_model=AuthResponse, tags=["auth"])
async def create_token(body: AuthRequest):
    """Issue a stub token for a given user_id (creates the user if needed)."""
    _ensure_user(body.user_id)
    return AuthResponse(
        token=f"stub-token-{body.user_id}",
        user_id=body.user_id,
    )


# ---- Ingest ---------------------------------------------------------------


@app.post("/ingest", response_model=IngestResponse, tags=["ingest"])
async def ingest(body: IngestRequest, user_id: str = Depends(_extract_user_id)):
    """Accept typing batches, tokenize, and update earnings."""
    _ensure_user(user_id)

    total_tokens = 0
    for batch in body.batches:
        tokens = enc.encode(batch.text)
        token_count = len(tokens)
        total_tokens += token_count

        user_batches[user_id].append(batch.model_dump())

    # Update ledger
    ledger = user_ledger[user_id]
    ledger["token_count"] += total_tokens
    ledger["balance"] += total_tokens * PAY_RATE
    ledger["lifetime_earnings"] += total_tokens * PAY_RATE

    # TODO: Write raw batches to object storage (S3/GCS) — data pipeline attaches here

    return IngestResponse(accepted=len(body.batches), tokens_counted=total_tokens)


# ---- Me -------------------------------------------------------------------


@app.get("/me/earnings", response_model=EarningsResponse, tags=["me"])
async def get_earnings(user_id: str = Depends(_extract_user_id)):
    """Return the authenticated user's earnings summary."""
    ledger = user_ledger[user_id]
    payouts = [
        PayoutEntry(**p) for p in payout_history.get(user_id, [])
    ]
    return EarningsResponse(
        token_count=ledger["token_count"],
        balance=ledger["balance"],
        lifetime_earnings=ledger["lifetime_earnings"],
        payout_history=payouts,
    )


@app.get("/me/export", response_model=ExportResponse, tags=["me"])
async def export_data(user_id: str = Depends(_extract_user_id)):
    """Export all stored data for the authenticated user (GDPR portable copy)."""
    ledger = user_ledger[user_id]
    payouts = [PayoutEntry(**p) for p in payout_history.get(user_id, [])]
    earnings = EarningsResponse(
        token_count=ledger["token_count"],
        balance=ledger["balance"],
        lifetime_earnings=ledger["lifetime_earnings"],
        payout_history=payouts,
    )
    return ExportResponse(
        user_id=user_id,
        batches=user_batches.get(user_id, []),
        earnings=earnings,
        exported_at=datetime.now(timezone.utc).isoformat(),
    )


@app.post("/me/delete", response_model=DeleteResponse, tags=["me"])
async def delete_data(user_id: str = Depends(_extract_user_id)):
    """Permanently delete all data for the authenticated user (GDPR right-to-erasure)."""
    user_ledger.pop(user_id, None)
    user_batches.pop(user_id, None)
    payout_history.pop(user_id, None)
    return DeleteResponse(
        deleted=True,
        message="All data has been permanently deleted",
    )


# ---- Payouts --------------------------------------------------------------


@app.post("/payouts/request", response_model=PayoutResponse, tags=["payouts"])
async def request_payout(
    body: PayoutRequest | None = None,
    user_id: str = Depends(_extract_user_id),
):
    """Request a payout. Defaults to the user's full balance if no amount is specified."""
    ledger = user_ledger[user_id]
    amount = (body.amount if body and body.amount is not None else ledger["balance"])

    if amount <= 0:
        raise HTTPException(status_code=400, detail="Nothing to pay out")
    if amount > ledger["balance"]:
        raise HTTPException(status_code=400, detail="Insufficient balance")

    # Deduct and record
    ledger["balance"] -= amount
    payout_id = str(uuid.uuid4())
    payout_record = {
        "amount": amount,
        "status": "pending",
        "requested_at": datetime.now(timezone.utc).isoformat(),
        "payout_id": payout_id,
    }
    payout_history.setdefault(user_id, []).append(payout_record)

    # TODO: Integrate with Stripe Connect API for real payouts

    return PayoutResponse(status="pending", amount=amount, payout_id=payout_id)


# ---------------------------------------------------------------------------
# Entrypoint (for `python main.py`)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
