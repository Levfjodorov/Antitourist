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

## Android 0.5.8

Places without an OSM Wikipedia/Wikidata link now look for Wikipedia articles by
name and coordinates. Up to three language editions are searched in parallel.
A real article within 250 m must match the point's name, a localized name or an
alternative name exactly after case/punctuation normalization. Wikipedia redirect
titles also count. Generic names, disambiguation pages and ambiguous matches to
different entities are rejected. Discovered text and the article's free Commons
photo load in the card with a name/coordinate match label and distance.

For linked and discovered articles, the chosen-language Wikipedia version is
preferred when available through an interlanguage link; otherwise on-device
translation remains available. Nearby Commons photos retain their separate 150 m
label. Coverage is limited to available Wikimedia material, not all websites.
Google Places Photos would require a separately configured API key and billing;
Google images and arbitrary website content are not scraped by this build.
Commons photos accept both official media hosts, including the new
`thumb.wikimedia.org` thumbnail domain, while retaining source and credit checks.

## Android 0.5.7

Version 0.5.7 keeps reflection-based ML Kit registrar names and constructors in
optimized APKs. Without these rules R8 removed constructors: the translation
plugin failed to register and every translation button raised MissingPluginException.

It also checks Wi-Fi before scheduling a model download, so initial cellular
retries cannot inherit a queued Wi-Fi-only task. Downloads have a five-minute
limit per model, duplicate taps are disabled, and retries retain explicit mobile
data permission for the open card. Errors show a specific reason and expandable
native diagnostics. A separate release-mode Android emulator job downloads
real models and requires Russian output for an Estonian monument description.

Version 0.5.6 translates linked article introductions, section headings and text
into the selected app language with Google Translate on-device models (ML Kit).
The original remains available through a toggle. Language models download over
Wi-Fi by default; a clearly labeled button allows mobile data. Once downloaded,
translation runs offline without sending the article text to a translation server.
Machine translations are labeled and include Google attribution. See the
[translation documentation](https://developers.google.com/ml-kit/language/translation)
and [Google Translate information](https://cloud.google.com/translate).

Version 0.5.5 loads photos and linked Wikipedia text automatically when a place
card opens. The native card shows article sections, including available history,
with source language, contributor attribution and licenses. No website needs to
be opened to read them. Successful downloads are reused during the app session;
failed downloads can be retried. Places without a linked article may have no
history, and nearby photos remain labeled as nearby. Switching languages reloads
the text and ignores responses for the previous language.

Version 0.5.4 uses a controlled embedded WebView: Android intent redirects use
validated HTTPS browser fallbacks, repeated redirects are stopped, and Google
Maps requests its desktop web page. Retry and browser history stay inside the app.
Device verification of Google Maps remains required.

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
- Test output: `dist/AntiTourist-0.5.8-test.apk`, checksums and build metadata.
- Release output: `dist/AntiTourist-0.5.8-release.apk`, using a permanent keystore.

The build pins Flutter in `.flutter-version`, enforces `mobile/pubspec.lock`,
runs analysis and tests before compiling, then verifies the APK signature,
application ID, version, permissions, and minimum SDK. Release signing requires
four Actions secrets and an explicit manual run from `main`; it never falls back
to a debug key. Each future release must increase the build number in `pubspec.yaml`.

Maps, live search, routing, and remote photos need internet. The Python backend
is independent of the current Android client. Open-data access flags do not
prove that a location is safe or publicly accessible.
