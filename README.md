# AntiTourist

AntiTourist is a travel app that builds routes around unusual, low-tourism places instead of the most popular attractions.

## MVP 0.1

- First city: Tallinn
- Modes: walking, cycling, driving
- Duration: 1–5 hours
- Interests: hidden, history, weird, views, food, industrial
- Core action: **Surprise Me**
- Each place has an **AntiTourist Score (0–100)**
- Safety rule: never recommend trespassing or clearly unsafe/private access

## Stack

- Mobile: Flutter
- API: FastAPI
- Database (next milestone): PostgreSQL + PostGIS
- Cache (next milestone): Redis
- Data sources (next milestone): OpenStreetMap / Overpass, Wikidata, optional Overture/Foursquare

## Run backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\\Scripts\\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open: http://127.0.0.1:8000/docs

Example:

```bash
curl -X POST http://127.0.0.1:8000/api/v1/routes/surprise \
  -H "Content-Type: application/json" \
  -d '{"lat":59.437,"lon":24.7536,"duration_minutes":120,"mode":"walking","interests":["history","weird","views"]}'
```

## Project status

This is the initial scaffold. The backend contains a working mock recommendation engine and tests. Real map data and routing are the next milestone.

## Android prototype 0.1.1

Android build scripts and a usable demo UI have been added. See
[Android instructions (Russian)](docs/ANDROID.md).

- Windows: `Build-APK.cmd` (requires Flutter, Android SDK, and Python).
- Other platforms: `python3 scripts/build_android.py`.
- GitHub Actions: manually run `Build Android APK` after importing this repository.
- Expected output after a successful build: `dist/AntiTourist-0.1.1-test.apk`.

**No APK is included in this archive.** Android tooling is unavailable in the
preparation environment. Flutter analysis, tests, APK compilation, and device
installation have not been run here. The scripts run Flutter analysis and tests
before building. The backend is unchanged from 0.1.

The local demo uses fictional points and runs without a server. Map tiles need
internet. These example points must not be used for a real walk. Road routing,
GPS, real place data, and turn-by-turn navigation are not implemented.
