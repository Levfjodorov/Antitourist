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

## Android 0.5.3

Version 0.5.3 fixes the stale on-screen version: the build script supplies the
same `pubspec.yaml` version to the app header, tests, and APK compiler.

Version 0.5.2 adds a full-screen photo gallery with pinch-to-zoom, photo retry,
and embedded browsing for Google Maps, Wikipedia and place websites. Photo
credits, licenses and nearby-photo distances stay visible. Android device
verification of the embedded websites is still required.

The mobile app supports live OpenStreetMap/Overpass place search, GPS and address
lookup, walking routes, saved walks, favorites, history, restart recovery, and
place details/photos when available. The interface supports Russian, Estonian,
and English. The demo points and the separate backend mock data are fictional.

**APK compilation is confirmed.**
[Actions run #12 on October 8, 2026](https://github.com/Levfjodorov/Antitourist/actions/runs/37747134686)
built `AntiTourist-0.5.1-test.apk` from commit `3b19872`: analysis passed and all
70 Flutter tests passed. The downloaded APK is 58,850,396 bytes and uses a debug
signing certificate. Installation and a physical-device smoke test are still
unverified. See [the build audit](docs/APK_BUILD_AUDIT.md).

See [Android build and release instructions (Russian)](docs/ANDROID.md).

- Windows: `Build-APK.cmd` (Python 3.10+, Flutter 3.47.6, Java 17, Android SDK).
- Linux/macOS: `python3 scripts/build_android.py`.
- GitHub Actions: `Build Android APK` runs on PRs and pushes to `main`, and supports manual runs.
- Test output: `dist/AntiTourist-0.5.3-test.apk`, checksums and build metadata.
- Release output: `dist/AntiTourist-0.5.3-release.apk`, using a permanent keystore.

The build pins Flutter in `.flutter-version`, enforces `mobile/pubspec.lock`,
runs analysis and tests before compiling, then verifies the APK signature,
application ID, version, permissions, and minimum SDK. Release signing requires
four Actions secrets and an explicit manual run from `main`; it never falls back
to a debug key. Each future release must increase the build number in `pubspec.yaml`.

Maps, live search, routing, and remote photos need internet. The Python backend
is independent of the current Android client. Open-data access flags do not
prove that a location is safe or publicly accessible.
