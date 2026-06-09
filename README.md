# Tally


## Architecture

```
┌─────────────────────────────────────────────────┐
│                 Companion App                    │
│  (SwiftUI — Onboarding, Dashboard, Controls)    │
│                                                  │
│  ┌──────────────┐  ┌──────────────────────────┐  │
│  │ Upload       │  │ BGTaskScheduler          │  │
│  │ Service      │──│ Periodic background wake │  │
│  └──────┬───────┘  └──────────────────────────┘  │
│         │                                        │
│         ▼                                        │
│  ┌──────────────────────────────────────┐        │
│  │     App Group Shared Container       │        │
│  │  ┌────────────┐  ┌───────────────┐   │        │
│  │  │ UserDefaults│  │ SQLite Buffer │   │        │
│  │  │ (consent,  │  │ (batches.db)  │   │        │
│  │  │  auth)     │  │               │   │        │
│  │  └────────────┘  └───────────────┘   │        │
│  └──────────────────────────────────────┘        │
│         ▲                                        │
│         │                                        │
│  ┌──────┴───────┐                                │
│  │   Keyboard   │                                │
│  │  Extension   │                                │
│  │  (appex)     │                                │
│  └──────────────┘                                │
└─────────────────────────────────────────────────┘
                    │
                    ▼  POST /ingest
         ┌─────────────────────┐
         │   FastAPI Backend   │
         │  (stub server)      │
         └─────────────────────┘
```

## Targets

| Target | Bundle ID | Type |
|--------|-----------|------|
| **Tally** | `com.BlackBeansInc.Tally` | iOS App (SwiftUI) |
| **TallyKeyboard** | `com.BlackBeansInc.Tally.TallyKeyboard` | Keyboard Extension |

## Prerequisites

- **Xcode 26.4+** (Swift 5, iOS 26.4 SDK)
- **Python 3.9+** (for the backend stub)
- Apple Developer account (for code signing and App Group provisioning)

## Setup

### 1. App Group Configuration

Both targets share an App Group container for consent flags, auth tokens, and the SQLite buffer.

1. Open the [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list/applicationGroup)
2. Register a new App Group: **`group.com.BlackBeansInc.Tally`**
3. Add this App Group to both the main app and keyboard extension App IDs
4. In Xcode, select each target → **Signing & Capabilities** → verify the App Group is checked

> The entitlements files (`Tally/Tally.entitlements` and `TallyKeyboard/TallyKeyboard.entitlements`) are already configured.

### 2. Build & Run the iOS App

1. Open `Tally.xcodeproj` in Xcode
2. Select the **Tally** scheme
3. Choose a simulator or device
4. Build and run (⌘R)

The keyboard extension (`TallyKeyboard`) is automatically built and embedded as a dependency.

### 3. Enable the Custom Keyboard

After installing the app on a device/simulator:

1. Go to **Settings → General → Keyboard → Keyboards → Add New Keyboard**
2. Select **Tally** from the third-party keyboards list
3. Tap **Tally** in the keyboard list → Toggle **Allow Full Access** ON
4. Accept the warning prompt

### 4. Backend Stub

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

The API is available at `http://localhost:8000`. See [backend/README.md](backend/README.md) for endpoint details.

> **Note:** The default API base URL in the iOS app is `http://localhost:8000`. For device testing, update to your machine's local IP.

## How It Works

### Consent Model

All data collection is **opt-in** and **granular**:

| Consent Flag | What It Controls |
|-------------|-----------------|
| `collect_text` | Whether typed text is captured |
| `collect_app_context` | Whether the host app bundle ID is recorded |
| `collect_typing_metadata` | Whether WPM and backspace rate are tracked |
| `collection_active` | Master kill switch — nothing is captured when OFF |

- Defaults are **OFF** until the user completes onboarding and explicitly enables collection
- The keyboard extension reads these flags from the shared `UserDefaults` on every keystroke batch
- Changes take effect **immediately** — flipping the toggle in the companion app is instantly respected by the keyboard

### Security Rules

The keyboard **NEVER** captures text from secure input fields (`isSecureTextEntry`). This includes:
- Password fields
- Credit card number fields
- Any field marked as secure by the host app

### Data Flow

1. **Keyboard captures** → Buffers text in memory → Flushes to shared SQLite every ~30 seconds
2. **Companion app wakes** (foreground or BGTaskScheduler) → Reads unuploaded batches → POSTs to `/ingest`
3. **Backend tokenizes** with tiktoken → Increments earnings ledger → Stores raw batches
4. **User sees** updated token count and balance in the Earnings dashboard

### Data Controls (GDPR/CCPA)

- **Pause**: Instantly stops all collection (master switch)
- **Export**: Download all your data as JSON
- **Delete**: Permanently wipe all data from server and local buffer

## Project Structure

```
Tally/
├── Shared/                    # Compiled into BOTH targets
│   ├── Models.swift           # Codable model types
│   ├── ConsentManager.swift   # App Group consent flags
│   ├── BufferDatabase.swift   # SQLite buffer wrapper
│   ├── AuthManager.swift      # Auth token storage
│   └── APIClient.swift        # HTTP client
├── Tally/                     # Companion App
│   ├── TallyApp.swift         # App entry point + BGTask
│   ├── Tally.entitlements     # App Group entitlement
│   ├── Views/
│   │   ├── OnboardingView.swift
│   │   ├── DashboardView.swift
│   │   ├── EarningsView.swift
│   │   ├── PayoutView.swift
│   │   ├── DataControlsView.swift
│   │   ├── SettingsView.swift
│   │   └── KeyboardSetupView.swift
│   └── Services/
│       └── UploadService.swift
├── TallyKeyboard/             # Keyboard Extension
│   ├── KeyboardViewController.swift
│   ├── KeyboardKeys.swift
│   ├── TypingMetrics.swift
│   ├── TallyKeyboard.entitlements
│   └── Info.plist
└── backend/                   # FastAPI Stub
    ├── main.py
    ├── requirements.txt
    └── README.md
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/auth/token` | Get a stub auth token |
| `POST` | `/ingest` | Submit typing data batches |
| `GET` | `/me/earnings` | Fetch earnings dashboard data |
| `GET` | `/me/export` | Export all user data as JSON |
| `POST` | `/me/delete` | Permanently delete all user data |
| `POST` | `/payouts/request` | Request a payout |

