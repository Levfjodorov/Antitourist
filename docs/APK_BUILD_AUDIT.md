# Android APK audit · 8 October 2026

Baseline: [`main` at `3b19872929a0ddde1a7124cd9adf3454361bfbfe`](https://github.com/Levfjodorov/Antitourist/commit/3b19872929a0ddde1a7124cd9adf3454361bfbfe), version **0.5.1+9**.
The previously referenced `4ba650d` is no longer HEAD.

## Confirmed build results

| Commit | Actions run | Result |
| --- | --- | --- |
| `4ba650d`, 0.5.0 | [#11, October 7](https://github.com/Levfjodorov/Antitourist/actions/runs/37643130862) | Analyze passed; 64 Flutter tests passed; APK built |
| `3b19872`, 0.5.1 | [#12, October 8](https://github.com/Levfjodorov/Antitourist/actions/runs/37747134686) | Analyze passed; 70 Flutter tests passed; APK built and artifact uploaded |

Artifact #12: [`AntiTourist-Android-test`](https://github.com/Levfjodorov/Antitourist/actions/runs/37747134686/artifacts/11536387334), expires October 22, 2026.
Its downloaded ZIP matches the GitHub artifact SHA-256:
`fd986ab182f33089c0736ded3ccde86efc0d9482cc30c2f9365c1e29ca69c495`.

| Downloaded APK property | Value |
| --- | --- |
| File | `AntiTourist-0.5.1-test.apk` |
| Size | 58,850,396 bytes |
| SHA-256 | `07d5e82a72895261c59e54fb529315448e508c8ec477b35fd9d35bc86fff16f6` |
| Signing certificate subject | `C=US,O=Android,CN=Android Debug` |
| Certificate SHA-256 | `ebb13f1d2ee043d4c64923dccd805bb5804e70a628228c45b3a3b3f1105a4771` |
| Native ABIs | `armeabi-v7a`, `arm64-v8a`, `x86_64` |
| Flutter / Dart | 3.47.6 / 3.13.5 |
| Application ID | `com.antitourist.antitourist` |
| Version name / code | `0.5.1` / `9` |
| Minimum Android SDK | 24 (Android 7.0) |
| Required permissions | INTERNET, ACCESS_COARSE_LOCATION, ACCESS_FINE_LOCATION |

The ZIP contains the APK, `flutter-version.json`, and `pubspec.lock`. Its lockfile
requires Dart >=3.12.0 and Flutter >=3.44.0. The lockfile is committed unchanged
as `mobile/pubspec.lock` in the proposed fixes.

The downloaded APK passes Android build-tools 36.0.0 `apksigner verify` and
`aapt dump badging`, including the new package-verification function. A locally
re-signed copy with a disposable keystore also passes the release-certificate
check; the original debug APK is rejected when that release certificate is
required. The disposable key and APK were removed after this check.

## Historical failures already fixed upstream

- [Run #5](https://github.com/Levfjodorov/Antitourist/actions/runs/37610911029)
  failed analysis on 12 Dart syntax/constant-expression errors in `lib/osm.dart`.
- [Run #8](https://github.com/Levfjodorov/Antitourist/actions/runs/37620947531)
  failed four Flutter tests, including taps outside the test viewport and a timeout.
- [Run #9](https://github.com/Levfjodorov/Antitourist/actions/runs/37622221892)
  still failed two UI tests. Commit `78e2ca7` fixed the lazy-list control finder;
  subsequent runs #10–#12 succeeded. These are not current APK blockers.

## Concrete fixes in this branch

| Finding | Fix |
| --- | --- |
| README and Android guide still described 0.1.1 and unexecuted builds | Record verified 0.5.0/0.5.1 builds and distinguish compilation from device validation |
| Flutter `stable`, Ubuntu `latest`, and uncommitted dependency resolution could drift | Pin Flutter 3.47.6 and Ubuntu 24.04; commit the known-good lockfile; use `--enforce-lockfile` and `--no-pub` |
| SDK constraints advertised Dart 3.6 although actual dependencies require 3.12 | Align pubspec SDK constraints with the verified lockfile |
| Raising the language version enabled two constructor lints in PR build #13 | Use Dart 3.12 private initializing formals in LanguageSettings, preserving public parameter names |
| SDK setup only requested platform-tools | Explicitly install API 36, build-tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1 matching the pinned Flutter toolchain |
| Workflow was manual-only and skipped Python build-script tests | Run on pull requests and main pushes; run build-script tests before APK compilation |
| Java, Android setup and artifact actions used deprecated Node 20 versions | Update to verified Node 24 action releases |
| All APKs used a temporary debug certificate | Add opt-in permanent signing with required secrets, main-only source guard and signer-certificate verification |
| Release-mode compilation alone did not prove package correctness | Verify APK signature, ID, versionCode/name, minSdk, release mode and permissions; produce metadata and SHA256SUMS |
| Template replacement could silently do nothing | Reject unknown Gradle templates; regenerate Android scaffolding with the pinned Flutter version |
| Reused dist could contain older APKs | Replace previous generated AntiTourist APKs only after a new package passes verification |

PR validation also loads the permanent-signing Gradle configuration with a
disposable key and verifies a re-signed copy of the actual compiled APK. The
disposable keystore and APK are removed and excluded from uploaded artifacts.
This checks the signing path without requiring or creating production secrets.

## Remaining release conditions

The repository has no published GitHub Releases at the time of the audit.
Compilation succeeds for test APKs, but a production-signed build requires the
owner's permanent keystore and four Actions secrets documented in
[ANDROID.md](ANDROID.md). A device smoke test and an update-install test remain
required before describing the APK as a verified device release. Google Play
distribution would additionally require an AAB and Play App Signing setup.
