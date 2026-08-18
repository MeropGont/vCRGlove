# vCRGlove Research Backend

Receives movement session data automatically from the iPhone app and provides a live clinical dashboard.

## Architecture

```
[iPhone — vCRGlove app]
    │  POST /sessions  (auto, after every recording)
    ▼
[FastAPI + SQLite]  ← port 8000
    │  reads
    ▼
[Streamlit Dashboard]  ← port 8501
    │  opens in browser
    ▼
[Clinician / Research team]
```

## Setup (UKE Backend Team)

### 1. Prerequisites
- Linux server with Docker + Docker Compose
- Accessible from the internet (patients use 4G/WiFi at home)
- Recommend: HTTPS via nginx reverse proxy + Let's Encrypt

### 2. Deploy
```bash
git clone <this repo>
cd backend/
cp .env.example .env
# Edit .env: set VCR_API_KEY to a long random string
docker compose up -d
```

API:       `http://<your-server>:8000`  
Dashboard: `http://<your-server>:8501`

### 3. Configure the iOS app
In `vCRGloveApp.swift`, replace the placeholder values:
```swift
SessionUploader.shared.configure(
    baseURL: URL(string: "https://vcr-backend.uke.de/api")!,
    apiKey: "YOUR_VCR_API_KEY"
)
```
Then rebuild and distribute the app to patients.

### 4. Dashboard access
Open `http://<your-server>:8501` in any browser.  
Enter the API key in the sidebar — the dashboard auto-refreshes every 30 seconds.

## API Reference

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/sessions` | Receive session from app (Bearer auth) |
| `GET`  | `/sessions` | List all trials (`?patient_id=` optional) |
| `GET`  | `/sessions/{id}` | Single session |
| `GET`  | `/export/metrics` | Download metrics CSV |
| `GET`  | `/health` | Liveness probe |

## Privacy & Security

- Patient data contains only a **pseudonymized ID** — no names or DOB
- All requests require a Bearer API key
- Database file is in a named Docker volume (survives container restarts)
- For production: add HTTPS termination via nginx/Caddy + restrict dashboard to VPN/Intranet
