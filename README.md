<div align="center">

# hyper_barcode

### Barcodify — barcode-driven price labels and a shared shopping list

**English** · [🇮🇷 فارسی](README.fa.md)

![Flutter](https://img.shields.io/badge/Flutter-3.24-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.5-0175C2?logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-minSdk_24-3DDC84?logo=android&logoColor=white)
![WordPress](https://img.shields.io/badge/WordPress-REST_API-21759B?logo=wordpress&logoColor=white)
![PHP](https://img.shields.io/badge/PHP-7.4%2B-777BB4?logo=php&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-offline_cache-003B57?logo=sqlite&logoColor=white)

</div>

> An Android workstation for retail **price labels** and a **family shopping list**: scan barcodes with the camera, mirror the store's WooCommerce catalogue into an offline SQLite cache, print millimetre-accurate PDF labels with Persian typography — and sync the shared list through a hardened WordPress REST API. ~9.6k lines of Dart on the client, ~8.1k lines of PHP on the server, both in this repository.

---

## Table of contents

- [1. The problem and the goal](#1-the-problem-and-the-goal)
- [2. What is in this repository](#2-what-is-in-this-repository)
- [3. Features](#3-features)
- [4. Architecture](#4-architecture)
- [5. Technology stack](#5-technology-stack)
- [6. Key engineering decisions](#6-key-engineering-decisions)
- [7. Build and run](#7-build-and-run)
- [8. Testing and verification](#8-testing-and-verification)
- [9. Known limitations and security notes](#9-known-limitations-and-security-notes)
- [10. Documentation](#10-documentation)

---

## 1. The problem and the goal

Small retailers live between two worlds: products and prices live in the store's systems (a Holoo POS feeding a WooCommerce shop), but **physical price labels** still have to be printed and stuck on shelves — and the household shopping list is a phone job, not a paper job.

Two hard requirements shaped this project:

1. **A label workstation that works on the shop floor** — scan a barcode, see the real name/cover/sale price, and produce a printable sheet at exact label dimensions (e.g. 70×42 mm) with correct Persian text, even when connectivity is flaky.
2. **A shared shopping list whose server survives reality** — clients retry, connections drop, the same request arrives twice. The WordPress side therefore implements a versioned sync protocol with immutable event snapshots, durable idempotency and a restart-safe backfill instead of naive CRUD.

## 2. What is in this repository

| Path | What it is |
|---|---|
| [`lib/`](lib/) | The Flutter client, feature-first layout: `core/` (config, logging, network, diagnostics, debug overlay) + `features/menu` + `features/shopping_list` — ~9.6k lines of Dart |
| [`wordpress-plugin/`](wordpress-plugin/) | **Barcodify Shopping List** — the REST API plugin (v1 `bl/v1` compatibility layer + hardened v2 `barcodify/v2`), ~8.1k lines of PHP, GPL-2.0, with its own test suites — see [wordpress-plugin/README.md](wordpress-plugin/README.md) |
| [`l10n/`](l10n/) | ARB localization for **fa** (default) and **en**, wired through `flutter gen-l10n` |
| [`android/`](android/) | Android host: `minSdk 24`, application id `com.barcodescanner.barcode_scanner_app` |
| [`.github/workflows/`](.github/workflows/) | CI: builds the debug APK on every push/PR and uploads it as an artifact |
| [`.trae/specs/`](.trae/specs/) | Tracked feature specs and task breakdowns for the shopping-list work |
| [`test/`](test/) | Flutter tests — still the stock template test (see [§8](#8-testing-and-verification)) |

## 3. Features

### Scanner and label workstation
- Continuous camera scanning (`mobile_scanner`) with scan-flash and animated check feedback; manual list entry alongside.
- Optional **remove-duplicates**, long-press multi-select with select-all / delete-selected, per-item remove.
- Product lookup by barcode against the local catalogue: the first barcode from the store's `_holoo_barcodes` metadata is the main barcode, the rest are alternates — every alternate resolves to the same product.
- **PDF price labels**: grid layout at exact millimetres (default **3 × 5 labels of 70 × 42 mm** per A4 page), configurable margins/gaps/row-column counts, cover price + sale price + barcode text, colours configurable; the template is persisted in `SharedPreferences`.
- The generated PDF is written to the app documents directory and shared through `share_plus` (print from any Android print service).
- Persian typography end-to-end: the **Vazirmatn** font is bundled and embedded into the PDF itself.

### Catalogue sync (WooCommerce → offline SQLite)
- Background, paginated sync (`per_page=50`) with a live progress bar and per-page accounting.
- **Retry policy**: up to 5 attempts per page; exponential backoff `1.5 s × 2ⁿ⁻¹ + jitter(0–1 s)`; growing timeouts (45 s first attempt, then 60 s + 15 s/attempt); timeouts, socket errors and client exceptions are classified, and a fresh HTTP client is opened after repeated failures.
- **Failure accounting instead of all-or-nothing**: failed pages are listed in the UI, the loop continues past them, and it stops early on `429`/`5xx` with whatever was fetched already saved.
- Writes are **batched into a single SQLite transaction**, upserting by `sku` (products table: sku, name, cover/sale price, main/extra barcodes, stock, last-synced).

### Shared shopping list
- Items with name, optional barcode, category/tag, purchased/pending filters; user profile (username + mobile) stored locally.
- Local-first: everything is written to SQLite first, then synced to the WordPress plugin over REST (currently the `bl/v1` endpoints — the v2 contract is the server-side successor, see [§9](#9-known-limitations-and-security-notes)).
- Provider-based state (`ShoppingListProvider`) with dedicated API/database services.

### App shell
- Full **fa/en localization** (Persian default, RTL) via `flutter gen-l10n`; Material 3 light/dark/system themes; language and theme persist across restarts.
- Operational tooling: structured `AppLogger`, an on-device **debug overlay**, a **connection diagnostics** screen that probes each backend endpoint, and a sync-status widget.

## 4. Architecture

```
┌────────────────────────  Flutter app (Android)  ─────────────────────────┐
│ MenuPage ─ ScannerPage: scan → lookup → PDF labels                      │
│          └ ShoppingListScreen (Provider + API/DB services)              │
│ Settings · DebugOverlay · AppLogger · ConnectionDiagnostics              │
└──────────────┬───────────────────────────────────┬──────────────────────┘
               │ read-only, paginated + retry      │ local-first sync
               ▼                                  ▼
   WooCommerce REST (wc/v3/products)   WordPress REST (bl/v1 today;
   catalogue: name, prices,            barcodify/v2 hardened protocol:
   _holoo_barcodes meta                snapshots · idempotency · backfill)
               │                                  │
               └──────────► SQLite ◄──────────────┘
                 products.db (catalogue cache)
                 + shopping-list tables
```

**Main flow:** `MenuPage` → scanner detects a barcode → local catalogue resolves name/price → label sheet built with the stored template → PDF generated and shared. The checklist screen reads/writes SQLite first and reconciles with the WordPress plugin over REST.

## 5. Technology stack

| Technology | Role in the project |
|---|---|
| **Flutter / Dart** (SDK `^3.5.0`, CI on 3.24.0) | Client app; single codebase, Material 3 |
| **mobile_scanner** | Camera barcode capture (continuous mode) |
| **sqflite** | Offline catalogue cache + shopping-list storage |
| **Provider** | State management (`ShoppingListProvider`, logger) |
| **pdf + printing** | Label sheets at exact millimetre geometry, embedded Persian font |
| **share_plus** | Hand the generated PDF to any Android share/print target |
| **http** | WooCommerce + WordPress REST calls with the retry policy above |
| **flutter_localizations + intl + gen-l10n** | fa/en ARB localization, RTL-first |
| **WordPress plugin (PHP 7.4+)** | Versioned REST sync API: custom `bl_*` tables, change logs, idempotency, rate limiting |
| **GitHub Actions** | Builds the debug APK on every push/PR (Java 17 + Flutter 3.24.0) |

## 6. Key engineering decisions

1. **Retry with classified errors, not a blind loop.** Timeouts, `SocketException`, and `ClientException` are handled separately; only retryable conditions consume the 5-attempt budget; backoff is exponential with jitter so parallel clients do not stampede the store.
2. **Failed pages are reported, not hidden.** The sync UI lists pages that failed and saves everything that succeeded — a partial catalogue that works beats a perfect one that never finishes.
3. **One transaction, keyed by SKU.** Batched upserts keep a full catalogue import in a single commit and make re-syncs idempotent by construction.
4. **The server protocol is designed for retries.** v2 keeps an **immutable `payload_json` snapshot per change event** (so replay order like `Milk → Milk 2 → DELETE → Milk 3` is exact), a **durable operation id** for `Idempotency-Key` creates (queryable at `GET /barcodify/v2/operations/{key}`, 90-day retention) and a **checkpointed, restart-safe backfill**.
5. **v1 is kept alive on purpose.** The current Flutter client speaks `bl/v1`; the plugin maintains it as a documented compatibility layer instead of breaking the shipped app.
6. **Persian is a first-class citizen.** Vazirmatn is the app font *and* is embedded into generated PDFs, so labels print with correct shaping regardless of the printer's font availability.
7. **Barcode model follows the store's reality.** One Holoo-sourced CSV metadata field (`_holoo_barcodes`) splits into a main barcode plus alternates, so every printed barcode scans back to the same product.
8. **Diagnostics ship with the app.** A debug overlay, structured logs and an endpoint-probing diagnostics screen exist because retail Wi-Fi is hostile.

## 7. Build and run

**Prerequisites:** Flutter 3.24+ (Dart SDK `^3.5.0`) · JDK 17 · an Android device/emulator on API 24+.

```bash
flutter pub get        # dependencies
flutter gen-l10n       # generate fa/en localizations
flutter run            # run on a connected device
```

```bash
flutter build apk --debug     # CI-equivalent build
# output: build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release   # local release build (sign with your own keystore)
```

**Continuous integration** — [.github/workflows/build.yml](.github/workflows/build.yml) runs on every push/PR to `main`/`master` (plus manual dispatch): Java 17 → Flutter 3.24.0 → `pub get` → `gen-l10n` → `flutter build apk --debug` → uploads the `app-debug` artifact. The release-build steps exist but stay commented until keystore secrets are provided.

**WordPress plugin:** copy [`wordpress-plugin/`](wordpress-plugin/) into `/wp-content/plugins/barcodify-shopping-list/` and activate it. Tables are created automatically with the `bl_` prefix; the schema-v5 migration and the resumable backfill run on activation. Full install/API reference: [wordpress-plugin/README.md](wordpress-plugin/README.md).

## 8. Testing and verification

The **WordPress plugin** carries the automated test load, in three layers that run **without a WordPress install** (plain PHP + PHPUnit):

```bash
cd wordpress-plugin
phpunit --testsuite pure        # unit/pure logic suites (a local tests/tools/phpunit-9.phar works too — it is gitignored, not shipped)
php tests/tools/real-source-check.php      # executes the real plugin source against WP stubs
php tests/tools/static-contract-check.php  # statically validates the integration suites' contracts
```

Integration suites (`--testsuite integration`) need a WordPress test bootstrap (`WP_TESTS_DIR`); without it they **self-skip with a clear message** while the pure suites still run. The suite covers cursor pagination determinism, tombstones, immutable snapshots, idempotent double-POSTs, revisions/conflicts, backfill resume, rate limiting and the v1 compatibility statement.

**CI** compiles the Flutter side (including `gen-l10n`) on every push and publishes the debug APK — the client's buildability is continuously proven.

> **Honest testing limitations:**
> - The Flutter test suite is still the **stock template test** and references a `MyApp` class that no longer exists, so `flutter test` is currently broken and is **not** run in CI. Replacing it with real widget/unit tests is the first roadmap item.
> - The PHP suites were not executed in this documentation pass (no PHP runtime on the writing machine); they are runnable exactly as documented in [wordpress-plugin/README.md](wordpress-plugin/README.md).
> - No live end-to-end run against the production store is part of this repository.

## 9. Known limitations and security notes

Recorded openly, in the same spirit as the audit notes inside `docs/API_V2.md`:

- **Store credentials must not live in the client.** The current client still embeds its WooCommerce *read* credentials in source; rotate them and move catalogue reads behind a server-side proxy before any wider distribution. (The plugin README states the same rule for the server side.)
- **v2 is public + rate-limited only.** Authentication is an explicit production gate before the hardened protocol faces the internet; v1 remains a compatibility layer.
- **The full v2 contract (`docs/API_V2.md`, 919 lines) is not published in this repository yet** (it is gitignored alongside local portfolio drafts), so the plugin README's link to it only resolves in local checkouts. Publishing it is a roadmap item.
- **`pubspec.lock` is gitignored** — for an application repo it should be committed for reproducible builds.
- The client still speaks **v1** while the server's hardened **v2** is the intended protocol; migration is pending.
- Release APK signing in CI is disabled pending keystore secrets.

### Roadmap (not implemented yet)

- Replace the stock Flutter test with real widget/unit tests + add `flutter analyze`/`flutter test` to CI.
- Migrate the client's shopping-list sync from `bl/v1` to the `barcodify/v2` cursor protocol.
- Publish `docs/API_V2.md`; commit `pubspec.lock`.
- Auth (JWT/OAuth) for v2, then enable the commented release build with a proper keystore.

## 10. Documentation

| Doc | Contents |
|---|---|
| [wordpress-plugin/README.md](wordpress-plugin/README.md) | Bilingual install guide, DB schema, every REST endpoint, test instructions |
| `docs/API_V2.md` (local checkout) | The 919-line normative sync contract: cursor semantics, snapshots, idempotency, backfill, security gates |
| [`.trae/specs/`](.trae/specs/) | Shopping-list feature specs and task breakdowns |

---

<div align="center">

**More from this portfolio:**
[HolooDB_Sync](https://github.com/DeathGunSR/HolooDB_Sync) ·
[Hyper_Event](https://github.com/DeathGunSR/Hyper_Event) ·
[WP-Recipe](https://github.com/DeathGunSR/WP-Recipe)

Maintained by [@DeathGunSR](https://github.com/DeathGunSR)

</div>
