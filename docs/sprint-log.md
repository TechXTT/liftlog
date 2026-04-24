# Sprint log

Committed audit trail of autonomous sprint boundaries. Mirrors the sprint-boundary blocks in `vault/current_state.md` so a reader who only has the repo (no vault) can reconstruct what shipped and why.

Format: one block per sprint. Newest first.

---

## Sprint 5 — E1 completion + E2 closeout (2026-04-24)

**Merges shipped**
- `52918df` chore(ios): HealthKit capability entitlement (direct-to-main chore)
- `7d759cd` S5.1 (#47/PR #53) exercise_id backfill via `beforeOpen`
- `958a937` S5.6 (#48/PR #54) Settings tab (6th nav tab; HK status + data + about)
- `9eb1ea4` S5.2 (#49/PR #55) HK-weight in Progress sparkline with day-bucket dedup
- `bf04201` S5.3 (#50/PR #56) HK HRV + resting HR + sleep façade (plumbing only)
- `1445341` S5.4 (#51/PR #57) HK workouts read + render on Workouts tab
- `1b4397e` S5.5 (#52/PR #58) Routines model (schema v3 → v4)

**Tests after:** 279/279.

**Schema:** v3 → v4 (additive: `routines`, `routine_exercises`). Manual backup path documented in vault Runbooks before code landed.

**Deps added:** `package_info_plus ^9.0.1`, `url_launcher ^6.3.2`. `device_info_plus 11.3.0` override retained (tracked for retirement).

**Decisions (full text in vault Decision Log):**
- S5.1 backfill via `beforeOpen` vs. new migration — chose beforeOpen (idempotent + no schema change).
- S5.2 dedup key = local calendar day; user-entered wins on tie per canonical Source precedence.
- S5.3 sleep façade returns raw per-stage samples; aggregation at consumer.
- S5.4 HK workouts render read-only; no auto-import into LiftLog's `WorkoutSessions`.
- S5.6 Export + Import moved from History → Settings.

**Blockers + resolution:** one transient Anthropic API overload during S5.2 dispatch (retried, resumed). No CI saga — all 6 PRs green on first CI attempt.

**Epics complete:** E1 HealthKit read-only foundation (body weight + HRV + resting HR + sleep + workouts). E2 Exercise + routines foundation (`Source` + exercises + routines + backfill). UI polish for routines + canonical-picker deferred to later sprints per "UI after epic" rule.

**Capacity read:** well-calibrated. 6 items in 5 waves. First-wave parallel dispatch (S5.1 + S5.6) serialized in practice because I wrote two consecutive Agent calls instead of firing both in one message. Noted for Sprint 6.

---

## Sprint 4 — v2.0 foundation (2026-04-24)

**Merges shipped**
- `3ed3894` S4.1 (#41/PR #44) JSON import (round-trip of #37 export)
- `6f90064` S4.2 (#42/PR #45) `Source` enum + exercises table + schema v3
- `8f42db0` S4.3 (#43/PR #46) HealthKit body-weight read + three supporting fix commits: `fc6cae0` (Podfile 13→16), `8a17cd7` (CI xcode-select 26.0.1), `8f42db0` (device_info_plus 11.3.0 override)
- Infra: `4bb0c4b` CI bootstrap (analyze + test + iOS build), `41b5b55`/`76b0715` diagnostic + removal

**Tests after:** 173/173.

**Schema:** v2 → v3 (additive: `source` column + `exercises` table + `exercise_id` FK). Manual backup path documented.

**Deps added:** `health ^13.3.1`. `dependency_overrides: device_info_plus: 11.3.0` (CI stopgap — GitHub's macos-latest runner only ships Xcode 26.0.1 which is missing an iOS 26.4+ selector that `device_info_plus 12.x` calls unguarded).

**Blockers + resolution:** S4.3 CI saga — 4 attempts before green (iOS deployment target bump → xcode-select → `device_info_plus` override). Documented in Skills.md as "CI Xcode version is a pinned dep" + "Plugin-stack `dependency_overrides` as a stopgap."

**Capacity read:** well-calibrated on shape. S4.3 CI consumed disproportionate time but the feature itself was tight.
