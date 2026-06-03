# Tally — Full Technical Reference

> Single source of truth for the **whole system**: client app, keyboard extension,
> shared storage, data models, and the client↔backend API contract.
> Written for engineers/agents working on **any** part of the stack (esp. the backend).

Tally is a **consented, paid data-collection** product. Users opt in, type with a custom
keyboard, and are **paid per token** of text they contribute. Everything is gated behind
explicit, revocable, per-category consent; secure fields are never captured.

---

## 1. System topology

```
 iOS Companion App (SwiftUI)              Custom Keyboard Extension (UIKit, .appex)
 ─ Onboarding / consent                   ─ Programmatic QWERTY + emoji + swipe-to-type
 ─ Dashboard (earnings/data/settings)     ─ Captures typed text WHEN consented
 ─ UploadService (BGTaskScheduler)        ─ Writes batches to shared SQLite
        │            ▲                              │
        │ reads/uploads                            │ writes
        ▼            │                              ▼
 ┌──────────────────────────────────────────────────────────┐
 │  App Group container:  group.com.BlackBeansInc.Tally       │
 │   • UserDefaults(suiteName:)  → consent flags + auth       │
 │   • buffer.sqlite             → unsent typing batches      │
 └──────────────────────────────────────────────────────────┘
        │
        │  HTTPS/JSON  (APIClient actor)
        ▼
 ┌──────────────────────────────────────────────────────────┐
 │  FastAPI backend (backend/main.py)  — currently in-memory  │
 │   POST /auth/token · POST /ingest · GET /me/earnings        │
 │   GET /me/export · POST /me/delete · POST /payouts/request  │
 └──────────────────────────────────────────────────────────┘
```

**The backend never talks to the device directly.** The app pulls batches out of the
local SQLite buffer and POSTs them to `/ingest`; everything else (earnings, export,
delete, payout) is request/response initiated by the app.

---

## 2. Repository / target layout

```
Tally/
├── Shared/                  # Compiled into BOTH the app and the keyboard targets
│   ├── Models.swift         # Codable request/response models (JSON contract)
│   ├── ConsentManager.swift # @Observable, UserDefaults-backed consent flags
│   ├── AuthManager.swift    # @Observable, UserDefaults-backed token + userId
│   ├── BufferDatabase.swift # Thread-safe SQLite3 C-API wrapper (nonisolated)
│   └── APIClient.swift      # actor; URLSession JSON client → baseURL
├── Tally/                   # App target (SwiftUI, iOS 17+)
│   ├── TallyApp.swift       # Entry, scenePhase, BGTaskScheduler registration
│   ├── Tally.entitlements   # App Group
│   ├── Services/UploadService.swift   # Background chunked upload worker
│   └── Views/               # Onboarding, Dashboard, Earnings, Payout, DataControls, Settings, KeyboardSetup
├── TallyKeyboard/           # Keyboard extension target (UIKit, UIInputViewController)
│   ├── KeyboardViewController.swift   # Layout, capture, emoji, swipe-to-type
│   ├── KeyboardKeys.swift             # Layouts + EmojiCatalog generator
│   ├── TypingMetrics.swift            # WPM / backspace-rate tracking
│   ├── words.txt                      # 9,884-word frequency list (swipe decoding)
│   ├── emoji-categories.txt           # Unicode emoji-test.txt, categorized
│   ├── TallyKeyboard.entitlements     # App Group
│   └── Info.plist                     # RequestsOpenAccess = true
└── backend/                 # FastAPI stub (main.py, requirements.txt)
```

- **No third-party Swift/Cocoa dependencies.** SQLite via the system `SQLite3` C API.
- **App Group ID** (shared by both targets): `group.com.BlackBeansInc.Tally`
- **Bundle IDs:** app `com.BlackBeansInc.Tally`, keyboard `com.BlackBeansInc.Tally.TallyKeyboard`
- Toolchain: Swift 5, Xcode 26.4 / iOS 26 SDK, strict concurrency
  (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`).

---

## 3. Shared storage

### 3.1 App-Group `UserDefaults` (suite `group.com.BlackBeansInc.Tally`)

| Key | Type | Owner | Meaning |
|-----|------|-------|---------|
| `collection_active` | Bool | ConsentManager | Master on/off for all capture |
| `collect_text` | Bool | ConsentManager | Consent to capture typed text |
| `collect_input_context` | Bool | ConsentManager | Consent to capture **field type** (e.g. "email"), never the app |
| `collect_typing_metadata` | Bool | ConsentManager | Consent to capture WPM / backspace rate |
| `has_completed_onboarding` | Bool | ConsentManager | Drives app entry (Onboarding vs Dashboard) |
| `has_accepted_terms` | Bool | ConsentManager | ToS + Privacy + Data License accepted |
| `auth_token` | String? | AuthManager | Bearer token (see §5.1) |
| `user_id` | String? | AuthManager | UUID issued at onboarding |
| `emoji_recents` | [String] | Keyboard | Recently used emoji (max 36) |

The keyboard reads these **live** on every keystroke, so toggling consent in the app
takes effect immediately in the extension.

### 3.2 SQLite buffer — `buffer.sqlite` (App-Group container)

`BufferDatabase` opens it with `PRAGMA journal_mode=WAL` + `busy_timeout=3000` so the app
and keyboard (separate processes) can read/write concurrently.

```sql
CREATE TABLE IF NOT EXISTS batches (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    text            TEXT    NOT NULL,
    app_context     TEXT,          -- field-type string or NULL
    wpm             REAL,          -- nullable
    backspace_rate  REAL,          -- nullable
    ts              TEXT    NOT NULL,   -- ISO-8601
    locale          TEXT    NOT NULL,   -- e.g. "en_US"
    uploaded        INTEGER DEFAULT 0   -- 0 = pending, 1 = uploaded
);
```

Lifecycle: keyboard `INSERT`s rows → app `SELECT … WHERE uploaded=0` → POSTs →
`UPDATE … SET uploaded=1` → `DELETE … WHERE uploaded=1` (reclaim space).
`BufferDatabase` degrades gracefully (no crash) if the container is unavailable.

---

## 4. Data models (the JSON contract)

All wire JSON is **snake_case**. Swift uses `CodingKeys` to map; FastAPI/pydantic uses the
same field names. Source of truth: `Shared/Models.swift` (client) and `backend/main.py`
(server). They must stay in sync.

### 4.1 Batch (the core unit of contributed data)

| JSON field | Type | Null? | Notes |
|-----------|------|-------|-------|
| `text` | string | no | The typed text for this batch |
| `app_context` | string | yes | Coarse field type: `text`/`email`/`url`/`number`/`phone`/`social`. **Never** the host app or its contents. Present only if `collect_input_context`. |
| `wpm` | number | yes | Words/min; present only if `collect_typing_metadata` |
| `backspace_rate` | number | yes | backspaces ÷ keystrokes; same gating |
| `ts` | string | no | ISO-8601 timestamp |
| `locale` | string | no | e.g. `en_US` |

> Swift `Batch` also has a local-only `id: Int64?` (SQLite row id). It is **not** sent in
> ingest payloads and is absent from server responses (decodes to `nil`).

### 4.2 Requests / responses

```
POST /auth/token
  req : { "user_id": "<uuid>" }
  res : { "token": "stub-token-<uuid>", "user_id": "<uuid>" }

POST /ingest                              (Bearer)
  req : { "user_id": "<uuid>", "batches": [ Batch, … ] }
  res : { "accepted": <int>, "tokens_counted": <int> }

GET  /me/earnings                         (Bearer)
  res : EarningsResponse

GET  /me/export                           (Bearer)
  res : { "user_id", "batches": [Batch…], "earnings": EarningsResponse, "exported_at": ISO8601 }

POST /me/delete                           (Bearer)
  res : { "deleted": true, "message": "…" }

POST /payouts/request                     (Bearer)
  req : { "amount": <number|null> }       # null ⇒ full balance
  res : { "status": "pending", "amount": <number>, "payout_id": "<uuid>" }
```

`EarningsResponse`:
```json
{
  "token_count": 0,            // int, lifetime tokens contributed
  "balance": 0.0,              // float USD, available to pay out
  "lifetime_earnings": 0.0,    // float USD, all-time
  "pay_rate": 0.0003,          // float USD per token
  "payout_history": [
    { "amount": 0.0, "status": "pending", "requested_at": "ISO8601", "payout_id": "uuid" }
  ]
}
```

> Client decodes `payout_history[].requested_at` and `payout_id` as **optional**, so the
> backend may omit them, but prefer to include them.

---

## 5. API contract details

`APIClient` (Shared/APIClient.swift) is an `actor`; `baseURL` defaults to
`http://localhost:8000`. **Set this to your production `https://` host for release** — and
note ATS: an `http://localhost` dev URL needs `NSAllowsLocalNetworking` (not yet configured).

| Method | Path | Auth | Client call |
|--------|------|------|-------------|
| GET  | `/` | — | (health) |
| POST | `/auth/token` | — | `authenticate(userId:)` |
| POST | `/ingest` | Bearer | `postIngest(batches:userId:token:)` |
| GET  | `/me/earnings` | Bearer | `getEarnings(token:)` |
| GET  | `/me/export` | Bearer | `exportData(token:)` |
| POST | `/me/delete` | Bearer | `deleteData(token:)` |
| POST | `/payouts/request` | Bearer | `requestPayout(amount:token:)` |

Non-2xx responses surface as `APIError.httpError(statusCode:data:)` on the client.

### 5.1 Auth model (STUB — replace for production)

- Onboarding generates a random `UUID` as `user_id`, calls `POST /auth/token`.
- The stub returns the token **`stub-token-{user_id}`**. The app stores it and sends it as
  `Authorization: Bearer stub-token-{user_id}` on every authed call.
- Backend `_extract_user_id` parses the `user_id` back out of that prefix and 401s if the
  user is unknown (e.g. after delete).
- **Production work:** swap this for real auth (e.g. signed JWT / session), keep the same
  endpoints and response shapes so the client needs no changes.

### 5.2 Token counting & pay model (backend)

- `tiktoken` `cl100k_base` encoder; `tokens_counted = len(enc.encode(text))` per batch.
- `PAY_RATE = 0.0003` USD/token. On ingest: `token_count += t`, `balance += t*rate`,
  `lifetime_earnings += t*rate`.
- Payout deducts from `balance`, appends a `pending` record to history.
- **Production integration points already marked with `TODO` in main.py:** real DB
  (replace the in-memory dicts), object storage for raw batches (S3/GCS at the `/ingest`
  handler), and Stripe Connect for `/payouts/request`. Data **sanitization/PII scrubbing**
  is expected to happen server-side in the ingest pipeline — the client sends raw text.

---

## 6. End-to-end data flows

**Capture → buffer (keyboard):** On each key/space/return/emoji/glide, if `shouldCapture`
is true, the char(s) append to an in-memory buffer and `TypingMetrics` updates. A 30s timer
(and `viewWillDisappear`) flushes the buffer into one SQLite row via `BufferDatabase.insertBatch`,
attaching `app_context`/`wpm`/`backspace_rate` only for the consented categories.

**`shouldCapture` gate (all must hold):** not a secure field (`isSecureTextEntry`) · keyboard
has Full Access · `collection_active` · `collect_text`. The green dot on the space bar
reflects this state live.

**Upload (app):** `UploadService.performUpload()` (nonisolated, runs off the main actor):
reads auth on the main actor → `fetchUnuploaded(limit:100)` → chunks of **50** → `POST /ingest`
per chunk → `markUploaded(ids:)` → `deleteUploaded()`. Triggered when the app becomes active
(`scenePhase`) and by a `BGAppRefreshTask` (`com.BlackBeansInc.Tally.upload`, ~15 min cadence).
Failed chunks stay in the DB for the next attempt.

**Earnings / Export / Delete / Payout:** direct request/response from the relevant view.
Delete also calls `BufferDatabase.deleteAll()` to purge the local buffer, and resets the
on-screen contributed/buffered counts.

---

## 7. Keyboard extension specifics

- Fully programmatic, responsive (proportional) QWERTY / numbers / symbols, plus an
  **emoji** mode (horizontal, category-tabbed, ~1,900 render-validated emoji from
  `emoji-categories.txt`, with a "Recent" section in `emoji_recents`).
- **Swipe-to-type** (QuickPath-style): SHARK²-style shape matching of the glide path against
  `words.txt`, pruned by start/end keys, weighted lightly by word frequency.
- Bottom row: `123 · 😀 · space("Tally" watermark) · . · return` — **no globe** (iOS provides
  keyboard switching in its own bottom bar).
- **Never captured:** secure fields, passwords, anything when consent/Full Access is off.
  Host-app identity is **not** collected (no private API); only the coarse field type.

---

## 8. Consent, privacy & legal

- Three independently-toggleable categories: **Typed Text**, **Input Context**, **Typing
  Metadata**. Master switch = `collection_active`.
- Onboarding (6 pages) requires explicit acceptance of **Terms of Service + Privacy Policy +
  Data License Agreement** and `collect_text` before finishing; per-category choices are
  respected (not force-enabled).
- GDPR/CCPA: in-app **Export** (`/me/export`) and **Delete** (`/me/delete` + local purge);
  consent is revocable instantly (Settings → pause, or Log Out → `revokeAllConsent`).

---

## 9. Backend (current vs. production)

**Current (`backend/main.py`, stub):** FastAPI, all state in Python dicts
(`user_ledger`, `user_batches`, `payout_history`), `tiktoken` counting, permissive CORS.
Run: `uvicorn main:app --reload --port 8000` (docs at `/docs`).

**Production checklist (what the backend work needs to deliver), keeping the §4–5 contract:**
1. Real datastore replacing the in-memory dicts (users, ledger, batches, payouts).
2. Real auth replacing `stub-token-{user_id}` (same endpoints/shapes).
3. Persist raw batches to object storage at `/ingest`; run **PII scrubbing / sanitization**
   in the ingest pipeline (client sends raw text by design).
4. Stripe Connect for `/payouts/request` (currently just records `pending`).
5. Keep `tokens_counted` semantics (tiktoken `cl100k_base`) and `pay_rate` so client
   earnings math stays consistent.

> Contract stability is the key constraint: as long as paths, JSON field names, and the
> Bearer-auth shape from §4–5 hold, the iOS client needs **zero** changes.
```
