# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## Wedge
A privacy-first, Apple-native personal fitness assistant. Ingests food, training, and HealthKit signals; surfaces opinionated, explainable options for what to do next. **Founder-first becoming a small-scale product** for a set of trusted paying users. iPhone + Apple Watch + iPadOS + HealthKit + CloudKit + StoreKit 2 + on-device Core ML.

## Before you implement anything
1. Read the target GitHub issue on `TechXTT/liftlog` (acceptance criteria, scope in/out, enums).
2. Read `vault/05 Architecture/Skills.md` — especially the **Flutter feature PR skill**, the **Drift + fake_async widget testing skill**, and **PR discipline skill**.
3. Read `vault/current_state.md` for where things stand today.
4. Ask only if a core assumption blocks you. Otherwise pick the simplest reasonable default and note it in the PR body.

## Non-goals (hard, v2.0)
- No social features, leaderboards, coaching marketplace, influencer / content features.
- No advertising.
- No Android. No Web.
- No non-Apple cloud (no AWS, GCP, Supabase, Firebase).
- No custom auth (signed into iCloud = authenticated).
- No third-party nutrition API (on-device Vision replaces it).
- No health or medical claims.
- No chatbot / free-text conversational AI. Coaching voice is parameterized templates, never a chat surface.
- No human-coach-in-the-loop.
- No marketing site, admin panel.
- No free tier. Free install = read-only view + JSON import/export. No new entries without trial or subscription.
- No multi-user shared CloudKit zones (trainer/client, couples) in v2.0.

Promotion rule: moving an item out of this list requires an explicit founder update to this file.

## Tech stack (v2.0)
- Flutter 3.41.7 (stable), Dart 3.11.5.
- Riverpod for state management.
- Drift + SQLite for local cache. CloudKit is the source of truth on conflict.
- HealthKit (read-only in E1; read+write later) via `health` package.
- On-device Core ML / Vision / Speech / Foundation Models (E6, E7).
- StoreKit 2 (E9) — on-device receipt validation, no server.
- Target platforms: **iOS + watchOS + iPadOS, Apple-only.** Apple Developer Program membership required ($99/yr, approved 2026-04-24).
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
- **No data model changes without a migration.** Schema changes require an explicit Drift migration + a documented manual backup path (`vault/05 Architecture/Runbooks.md`).
- **No hidden auto-adjustment of calorie / macro targets.**
- **Provenance is a first-class column.** Every entity records its `Source` (`user_entered`, `saved_template`, `health_kit`, `photo_estimate`, `voice_estimate`, `barcode`, `derived`, `imported`). Never mix without a visible source badge. `FoodEntryType` stays semantic (meal categorization); `Source` is orthogonal provenance.
- **Source precedence:** `user_entered` > `saved_template` > `health_kit` > `derived` > `imported`. Never invert.
- **On-device-only intelligence.** No food / training / HK data leaves the device unencrypted. CloudKit E2E is the only sync path.
- **Surface observations and tradeoffs. Never prescribe. Never infer a condition.** Every surfaced recommendation names the signal, offers at least two options, and ends with user agency. No single imperatives. Example: *"HRV has trended down 7 days. Options: cut Thursday bench volume ~20%, swap to technique work, or push through if you feel solid — your call."*
- **Every recommendation exposes its inputs in a one-tap "why" view.** If a decision can't be explained from logged data, it doesn't ship. No black-box heuristics.
- **Every decision is overridable.** No silent apply, no non-dismissable change. Override preserves the original proposal for audit.
- **Signal, not judgment.** Copy reports what happened, never what the user did wrong. "Your HRV is trending down" not "You didn't recover."
- **Sync-off is pause, not fork.** Turning CloudKit off preserves the local DB and stops pushing. Re-enabling resumes from the existing local state; CloudKit change tokens handle merging. Never a dual-copy reconciliation.
- **Entitlement never blocks access to a user's own logged data or the core v1 tracking loop.** A lapsed subscription preserves the full local DB, keeps creating, editing, deleting, importing, and exporting entries working, and pauses everything v2 adds on top: CloudKit sync, coaching voice, adaptive programming, Watch sync, HealthKit writes, and any future gated feature. Data is never deleted or obscured. The app degrades to a v1-equivalent local tracker, not a read-only museum.

## Number + unit formatting
- Numbers rendered next to a unit MUST go through `lib/ui/formatters.dart` (`formatKcal`, `formatGrams`, `formatWeight`).
- Never hand-roll `'$x kg'` / `'$x g'` / `'$x kcal'` interpolations in feature code.
- This rule supports the units guardrail above and keeps display behavior centralized.

## Canonical enums
Enumerate every value when adding a `switch`/dropdown — no fallthrough defaults.

- Meal type: `breakfast`, `lunch`, `dinner`, `snack`, `other`
- Goal type: `fat_loss`, `maintenance`, `muscle_gain` (not in UI yet; reserved)
- Entry type (meal categorization only): `manual`, `saved_food`, `barcode`, `estimate`
- Units: `kg`, `lb`, `cm`, `in`, `kcal` (only `kg` / `lb` / `kcal` used today)
- Workout set status: `planned`, `completed`, `skipped`
- **Source (orthogonal to Entry type):** `user_entered`, `saved_template`, `health_kit`, `photo_estimate`, `voice_estimate`, `barcode`, `derived`, `imported`
- **Entitlement state (StoreKit):** `active`, `in_trial`, `lapsed`, `grandfathered`, `never_subscribed`

## Entitlement state — behavioral policy

| State | Core v1 loop (create/edit/delete food+weight+workouts) | JSON export | JSON import | v2 features |
|---|---|---|---|---|
| `never_subscribed` | **No new entries.** Import allowed as one-time restore. | ✓ | ✓ | paused |
| `in_trial` | ✓ | ✓ | ✓ | ✓ |
| `active` | ✓ | ✓ | ✓ | ✓ |
| `grandfathered` | ✓ | ✓ | ✓ | ✓ |
| `lapsed` | ✓ (full v1 loop, local-only) | ✓ | ✓ | **paused** (CloudKit sync, coaching voice, adaptive programming, Watch sync, HealthKit writes) |

Import is treated as restoration, not creation. It is available in every state that can read data.

Key rule: the paywall gates **v2 adds**, not the v1 core. A lapsed subscription degrades the app to v1-equivalent behavior; it does not create a read-only state. A never-trialed fresh install blocks *new* entries (trial-or-subscribe to start logging) but allows one-time JSON restore so a user can evaluate the app against a prior backup.

## Platform-risk guardrails
- All persistence writes for logged data must be awaited; errors must surface to the UI. No fire-and-forget writes.
- Assume iOS storage can fail or be revoked by the OS. Detect, report, and halt — do not silently fall back to in-memory state.
- Before any schema migration: document the manual backup path in `vault/05 Architecture/Runbooks.md` and ensure the migration is reversible or the backup restorable.

## Apple Watch — companion target (E4)
- Keep models pure Dart. No UIKit types, no `BuildContext`, no phone-screen-derived values in `lib/data/**` or `lib/sources/**`.
- Drift + `lib/sources/**` are the **only** data-access boundaries. Features never touch them directly.
- Every `watch*()` on a repo has a `list*()` one-shot sibling (Watch + widgets depend on one-shots).
- Watch read-state comes from CloudKit-synced data; Watch is not authoritative for edits.

## Platform-bridged sources (`lib/sources/`)
HealthKit, Vision, Speech, StoreKit, and any future Apple-only data source lives under `lib/sources/<name>/`.
- Bridge code (method channels / Flutter plugins) lives only in this layer.
- Pure-Dart interfaces are exposed to the rest of the app.
- Feature code (`lib/features/`) never imports from `lib/sources/<name>/` implementation files — only from the public interface façade (same rule that applies to `lib/data/`).
- Arch guardrail (`test/arch/data_access_boundary_test.dart`) enforces this.
- Entitlement state from StoreKit lives in CloudKit zone metadata, not in Drift.

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
- **Do not merge until required CI checks are green.** See CI section below.
- Merge via `--rebase --delete-branch`.

## CI (GitHub Actions)
Workflow at `.github/workflows/ci.yml` runs on every push to `main` and every pull request targeting `main`. On `macos-latest` (for the iOS build step), it executes in order:
1. `flutter pub get`
2. `flutter analyze` — must be clean.
3. `flutter test --timeout=60s` — must pass.
4. `flutter build ios --debug --no-codesign` — catches Podfile / Info.plist / asset regressions.

Required for merge: all four steps green. Local subagents / PM should still run the same commands before pushing — CI is independent verification, not a replacement for local checks.

Pinned Flutter version in CI must match the "Tech stack (actual)" section above. Bump both together.

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
