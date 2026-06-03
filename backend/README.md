# Tally — Backend API (Stub)

A lightweight FastAPI stub backend for the Tally ethical data-collection platform. All data is stored **in-memory** — this is a development scaffold, not a production service.

---

## Quick Start

```bash
cd backend

# Create a virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run the server
uvicorn main:app --reload --port 8000
```

The API will be available at **http://localhost:8000**. Interactive docs live at **http://localhost:8000/docs**.

---

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/` | — | Health check |
| `POST` | `/auth/token` | — | Issue a stub token for a user |
| `POST` | `/ingest` | Bearer | Accept typing batches and count tokens |
| `GET` | `/me/earnings` | Bearer | View earnings summary |
| `GET` | `/me/export` | Bearer | Export all user data (GDPR) |
| `POST` | `/me/delete` | Bearer | Delete all user data (GDPR) |
| `POST` | `/payouts/request` | Bearer | Request a payout |

### Authentication

This stub uses a simple token scheme for development:

```
POST /auth/token
{ "user_id": "alice" }
→ { "token": "stub-token-alice", "user_id": "alice" }
```

Pass the token in subsequent requests:

```
Authorization: Bearer stub-token-alice
```

### Ingest Example

```bash
curl -X POST http://localhost:8000/ingest \
  -H "Authorization: Bearer stub-token-alice" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "alice",
    "batches": [
      {
        "text": "Hello world, this is a test.",
        "app_context": "com.example.notes",
        "wpm": 72.5,
        "backspace_rate": 0.03,
        "ts": "2026-06-02T20:00:00Z",
        "locale": "en-US"
      }
    ]
  }'
```

### Payout Example

```bash
curl -X POST http://localhost:8000/payouts/request \
  -H "Authorization: Bearer stub-token-alice" \
  -H "Content-Type: application/json" \
  -d '{ "amount": 0.50 }'
```

---

## Stub Notes

> **⚠️ This is a development stub.** The following components are intentionally simplified and require real implementations before production use:

- **Storage** — All data lives in Python dicts and is lost on restart. Replace with PostgreSQL, DynamoDB, or similar.
- **Auth** — Tokens are deterministic strings (`stub-token-{user_id}`). Replace with JWT / OAuth 2.0.
- **Object Storage** — Raw typing batches should be persisted to S3 / GCS for the data pipeline.
- **Payouts** — Payout requests are recorded in-memory with status `"pending"`. Integrate with Stripe Connect for real disbursements.
- **Rate Limiting** — No rate limiting is applied. Add middleware or an API gateway in production.

---

## Project Structure

```
backend/
├── main.py              # FastAPI application (all endpoints)
├── requirements.txt     # Python dependencies
└── README.md            # This file
```
