# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## Wedge
A simple personal Flutter app for tracking calories, protein, body metrics, and gym workouts with minimal friction. Single-user, founder-first, **iPhone-first**.

## Before you implement anything
1. Read the target GitHub issue on `TechXTT/liftlog` (acceptance criteria, scope in/out, enums).
2. Read `vault/05 Architecture/Skills.md` — especially the **Flutter feature PR skill**, the **Drift + fake_async widget testing skill**, and **PR discipline skill**.
3. Read `vault/current_state.md` for where things stand today.
4. Ask only if a core assumption blocks you. Otherwise pick the simplest reasonable default and note it in the PR body.

## Non-goals (explicit, v1)
- No social features, coaching marketplace, admin panel, marketing site.
- No Android support in v1. Do not add Android-specific files, plugins, or platform code without explicit direction.
- No wearable integrations in v1. Apple Watch is a **future** track — keep data models and app structure portable, but do not ship watch features.
- No advanced AI features.
- No cloud sync until local persistence is stable.
- No barcode scanning or third-party nutrition API in v1.
- No health or medical claims anywhere in copy or UI.
- No paywall / subscription.

Promotion rule: moving an item out of this list into implementation scope requires an explicit founder update to this file.

## Tech stack (actual)
- Flutter 3.41.7 (stable), Dart 3.11.5.
- Riverpod for state management.
- Drift + SQLite for local persistence (via `path_provider`).
- Target platform: **iOS only**. `flutter create --platforms=ios`.
- Signing: `DEVELOPMENT_TEAM = LQGYT7RS92`, bundle id `dev.techxtt.liftlogApp`.

## Deploy target
- Development: iOS Simulator (Xcode 26 ships iPhone 17-series sims; **no iPhone 15 Simulator** — use an iPhone 17 variant or the physical iPhone 15).
- Device install: local run from Xcode to the founder's iPhone 15 (device id `00008150-001A22383620401C`).
- No TestFlight, no App Store in v1.

## Commands
```
flutter pub get                         # install deps
flutter analyze                         # static analysis / lint
dart format --set-exit-if-changed .     # formatting check
flutter test                            # all tests
flutter test test/foo_test.dart         # single test file
flutter test --plain-name "foo"         # tests matching name
flutter devices                         # list available iOS devices / simulators
flutter build ios --debug --no-codesign # debug iOS build (simulator-safe, no run)
flutter build ios --release             # release iOS build (signing required)
```

Drift / build_runner — regenerate after changing a `@DriftDatabase` table:
```
dart run build_runner build --delete-conflicting-outputs
```

iOS native deps:
```
cd ios && pod install && cd -           # after adding a plugin with native deps
```

After `flutter build ios ...`, always `flutter clean` before a subsequent `flutter run` on a different target (prevents stale `build/ios/iphoneos/` from confusing target selection).

## Domain safety rules (trust-critical)
- **No silent fallbacks** when a food or workout save fails. Surface the error; do not mutate totals.
- **No silent mutation of calorie / macro totals.** Totals are derived from logged entries — never "adjust" them behind the user's back.
- **Delete flows must be explicit and confirmed.** Never delete logged entries without an explicit confirm step.
- **Units must be defined clearly** at model, storage, and UI layer. Never mix kg/lb, cm/in, or kcal/kJ within a single flow. Never silently convert.
- **Estimates must be visibly labeled** in the UI as estimates. Never present an estimated value as directly logged.
- **Data source precedence:** `user_entered` > `saved_template` > `default`. Never invert.
- **No data model changes without a migration.** Schema changes require an explicit Drift migration + a documented manual backup path (`vault/05 Architecture/Runbooks.md`).
- **No hidden auto-adjustment of calorie / macro targets.**

## Number + unit formatting
- Numbers rendered next to a unit MUST go through `lib/ui/formatters.dart` (`formatKcal`, `formatGrams`, `formatWeight`).
- Never hand-roll `'$x kg'` / `'$x g'` / `'$x kcal'` interpolations in feature code.
- This rule supports the units guardrail above and keeps display behavior centralized.

## Canonical enums
Enumerate every value when adding a `switch`/dropdown — no fallthrough defaults.

- Meal type: `breakfast`, `lunch`, `dinner`, `snack`, `other`
- Goal type: `fat_loss`, `maintenance`, `muscle_gain` (not in UI yet; reserved)
- Entry type: `manual`, `saved_food`, `barcode`, `estimate` (only `manual` / `estimate` exposed in UI today)
- Units: `kg`, `lb`, `cm`, `in`, `kcal` (only `kg` / `lb` / `kcal` used today)
- Workout set status: `planned`, `completed`, `skipped`
- Data source precedence: `user_entered` > `saved_template` > `default`

## Platform-risk guardrails
- All persistence writes for logged data must be awaited; errors must surface to the UI. No fire-and-forget writes.
- Assume iOS storage can fail or be revoked by the OS. Detect, report, and halt — do not silently fall back to in-memory state.
- Before any schema migration: document the manual backup path in `vault/05 Architecture/Runbooks.md` and ensure the migration is reversible or the backup restorable.

## Apple Watch — architectural caution (no v1 features)
Kept portable now; cheaper than retrofit later.
- Keep models pure Dart. No UIKit types, no `BuildContext`, no phone-screen-derived values in `lib/data/**`.
- Drift repositories are the **only** data-access boundary. UI does not call `db.select(...)` directly.
- Every `watch*()` on a repo has a `list*()` one-shot sibling (keeps a future non-UI consumer honest).
- Do not add WatchConnectivity, watchOS targets, or companion app code.

## Mobile viewport / device assumptions
- iPhone 15 (portrait). Logical viewport 393×852. Touch targets ≥ 44 pt.
- **PM verification is code-level only** (2026-04-23 policy): `flutter analyze` + `flutter test` + `flutter build ios --debug --no-codesign`. Device / simulator runs are founder-initiated.

## Secrets hygiene
- v1 expects no secrets (local-first, no backend, no third-party APIs).
- If a secret is introduced: name it in the PR description; value lives in env / deploy config only. Never commit values.
- Gitignore any `.env` before use.

## Env-gated code
Any environment-sensitive code path defaults to the **prod-safe** behavior when the env var is unset.

## Dependencies
Keep `pubspec.yaml` dependencies minimal. Every new dependency must be justified in the PR body (why this one; what was considered).

## Branching / PR hygiene
- Base branch: `main`.
- PR title: `#<issue> — <short summary>`.
- One commit per PR when feasible; if multi-commit, each commit tells a distinct story.
- PM verifies PR base = `main` and commit scope on PR-open, before merge.
- Merge via `--rebase --delete-branch`.

## Gitignore
- `vault/` **must** stay in `.gitignore`. Vault is long-term memory on disk, never committed.
- Standard Flutter `.gitignore` + `vault/`, `.env*`, `.claude/settings.local.json`, macOS/IDE detritus.

## Design reference (committed)
- `docs/design/README.md` — visual + copy contract: color tokens, type scale, iconography, empty-state / delete-confirm / validation copy recipes, forbidden vocabulary. Read this before any UI-touching change. When it disagrees with this file, this file wins.
- `docs/design/tokens.css` — M3 CSS variable set (reference only; app reads from `ThemeData` at runtime).
- `docs/design/assets/` — draft brand marks (not yet the app icon — founder decision pending).
- `docs/export-format.md` — authoritative JSON shape for the Export all data (JSON) flow on the History tab. Bump `format_version` whenever the shape changes.

## Process references (vault = memory, not committed)
- Strategy: `vault/01 Strategy/Strategy Memo.md`
- Roadmap: `vault/02 Roadmap/Roadmap.md`
- Current sprint: `vault/02 Roadmap/Sprint Plan Current.md`
- Mode: `vault/02 Roadmap/Mode.md`
- Decisions: `vault/03 Decisions/Decision Log.md`
- Incidents: `vault/04 Incidents/Incident Log.md`
- PM improvements: `vault/04 Incidents/PM Improvements Log.md`
- Runbooks: `vault/05 Architecture/Runbooks.md`
- Subagents: `vault/05 Architecture/Subagents.md`
- Skills: `vault/05 Architecture/Skills.md`
- Current state: `vault/current_state.md`
