# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Wedge
A simple personal Flutter app for tracking calories, protein, body metrics, and gym workouts with minimal friction. Single-user, founder-first, **iPhone-first**.

## Non-goals (explicit)
- No social features, coaching marketplace, admin panel, marketing site.
- No Android support in v1. Do not add Android-specific files, plugins, or platform code without explicit direction.
- No wearable integrations in v1. Apple Watch is a **future** track — keep data models and app structure portable, but do not ship watch features in sprint 1.
- No advanced AI features.
- No cloud sync until local persistence is stable.
- No barcode scanning or third-party nutrition API in v1.
- No health or medical claims anywhere in copy or UI.

## Tech stack (confirmed)
- Flutter — stable channel; exact version pinned in `pubspec.yaml` once scaffolded.
- Dart — version follows Flutter channel.
- Riverpod for state management.
- Drift + SQLite for local persistence (via `path_provider`).
- Target platform: **iOS only**. Scaffold with `flutter create --platforms=ios`.

## Deploy target
- Development: iOS Simulator.
- Device install: local run from Xcode to the founder's iPhone 15.
- No TestFlight, no App Store in v1.

## Commands
When the Flutter app is not yet scaffolded, these will error — say so rather than guessing.

```
flutter pub get                         # install deps
flutter analyze                         # static analysis / lint
dart format --set-exit-if-changed .     # formatting check
flutter test                            # all tests
flutter test test/foo_test.dart         # single test file
flutter test --plain-name "foo"         # tests matching name
flutter run -d "iPhone 15"              # run on iPhone 15 Simulator
flutter devices                         # list available iOS devices / simulators
flutter build ios --debug --no-codesign # debug iOS build (simulator-safe)
flutter build ios --release             # release iOS build (signing required)
```

If Drift / freezed / build_runner are present, regenerate after changing generated models:
```
dart run build_runner build --delete-conflicting-outputs
```

iOS-specific:
```
cd ios && pod install && cd -           # after adding a native-dependency plugin
```

## Domain safety rules (trust-critical)
- **No silent fallbacks** when a food or workout save fails. Surface the error; do not mutate totals.
- **No silent mutation of calorie / macro totals.** Totals are derived from logged entries — never "adjust" them behind the user's back.
- **Delete flows must be explicit and confirmed.** Never delete logged entries without an explicit confirm step.
- **Units must be defined clearly** at model, storage, and UI layer. Never mix kg/lb, cm/in, or kcal/kJ within a single flow.
- **Estimates must be visibly labeled** in the UI as estimates. Never present an estimated value as directly logged.
- **Data source precedence:** `user_entered` > `saved_template` > `default`. Never invert.
- **No data model changes without a migration.** Schema changes require an explicit Drift migration and a documented manual backup path (`vault/05 Architecture/Runbooks.md`).
- **No hidden auto-adjustment of calorie / macro targets.**

## Canonical enums
Enumerate every value when adding a case — no fallthrough defaults.

- Meal type: `breakfast`, `lunch`, `dinner`, `snack`, `other`
- Goal type: `fat_loss`, `maintenance`, `muscle_gain`
- Entry type: `manual`, `saved_food`, `barcode`, `estimate`
- Units: `kg`, `lb`, `cm`, `in`, `kcal`
- Workout set status: `planned`, `completed`, `skipped`
- Data source precedence: `user_entered` > `saved_template` > `default`

## Platform-risk guardrails
- All persistence writes for logged data must be awaited; errors must surface to the UI. No fire-and-forget writes.
- Assume iOS storage can fail or be revoked by the OS. Detect, report, and halt — do not silently fall back to in-memory state.
- Before any schema migration: document the manual backup path in `vault/05 Architecture/Runbooks.md` and ensure the migration is reversible or the backup restorable.

## Apple Watch — architectural caution (no v1 features)
- Keep `FoodEntry`, `WorkoutSession`, `ExerciseSet`, `BodyWeightLog` models portable: no iOS-phone-only assumptions baked in (e.g., do not store UIKit-specific types or phone-screen-derived values in the model layer).
- Prefer a clean data-layer boundary (Drift repositories) so a future watch companion can read/write through it.
- Do not add WatchConnectivity, Watch-specific targets, or companion app code in sprint 1.

## Mobile viewport / device assumptions
- iPhone 15 (portrait). Logical viewport 393×852.
- Touch targets ≥ 44 pt.
- QA must include a run on the iPhone 15 Simulator (at minimum) before closing a user-facing issue.

## Secrets hygiene
- v1 expects no secrets (local-first, no backend, no third-party APIs).
- If a secret is introduced: name it in the PR description; value lives in env / deploy config only. Never commit values.
- Gitignore any `.env` before use.

## Env-gated code
- Any environment-sensitive code path must default to the **prod-safe** behavior when the env var is unset.

## Dependencies
- Keep `pubspec.yaml` dependencies minimal. Every new dependency must be justified in the PR body (why this one; what was considered).

## Branching / PR hygiene
- Base branch: `main`.
- PR title references the GitHub Issue number (e.g., `#3 — Scaffold Flutter iOS app`).
- PM verifies PR base = `main` and commit scope on PR-open, before CI.

## Gitignore
- `vault/` **must be in `.gitignore`**. The vault is long-term memory on disk and must not be committed.
- Standard Flutter `.gitignore` plus `vault/`, `.env*`, and macOS/IDE detritus.

## Process references (vault = memory, not committed)
- Vault location: `vault/` at repo root.
- Strategy: `vault/01 Strategy/Strategy Memo.md`
- Roadmap: `vault/02 Roadmap/Roadmap.md`
- Current sprint: `vault/02 Roadmap/Sprint Plan Current.md`
- Mode: `vault/02 Roadmap/Mode.md`
- Decisions: `vault/03 Decisions/Decision Log.md`
- Incidents: `vault/04 Incidents/Incident Log.md`
- PM improvements: `vault/04 Incidents/PM Improvements Log.md`
- Runbooks: `vault/05 Architecture/Runbooks.md`
- Subagents: `vault/05 Architecture/Subagents.md`
- Current state: `vault/current_state.md`
