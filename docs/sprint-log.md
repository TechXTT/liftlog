# Sprint log

Committed audit trail of autonomous sprint boundaries. Mirrors the sprint-boundary blocks in `vault/current_state.md` so a reader who only has the repo (no vault) can reconstruct what shipped and why.

Format: one block per sprint. Newest first.

---

## Sprint 7 — E3 custom CloudKit MethodChannel kickoff + UI polish (2026-04-25)

**Merges shipped**
- `5503e53` S7.1 (#69/PR #74) Custom CloudKit MethodChannel scaffolding (walking skeleton — `getAccountStatus()` + `lib/sources/cloudkit/` façade + `ios/Runner/CloudKit/` bridge) — Wave 1
- `c688b09` S7.4 (#72/PR #75) Workout session notes UI (surfaces existing `WorkoutSession.note`; pre-fills from `Routines.notes` on start-from-routine) — Wave 1
- `7765a9a` S7.2 (#70/PR #76) Typed CloudKit record save + fetch (`[typeTag, raw]` wire contract preserves Int/Double/DateTime/Bool fidelity) — Wave 2
- `5e5f4ac` S7.5 (#73/PR #77) Group sets by exercise on session detail (LEFT OUTER JOIN on `exercises`; canonical-vs-legacy bucketing with "(legacy)" suffix) — Wave 2
- `b137f0f` S7.3 (#71/PR #78) CloudKit record zones + zone-scoped record IDs (`ensureZoneExists` + `kLiftLogZoneName` + cross-zone isolation) — Wave 3

**Tests after:** 427/427. +87 over Sprint 6 boundary (340).

**Schema:** Unchanged (v5). No migrations this sprint.

**Deps added:** none. All E3 work is custom Swift + Dart inside `lib/sources/cloudkit/` and `ios/Runner/CloudKit/`. The 2026-04-24 PIVOT decision (no `flutter_cloud_kit`) held cleanly through implementation.

**Decisions recorded (Decision Log):** none new. Sprint 7 was straight execution against the spike's Sprint 7 issue skeleton (S7.1–S7.3 in spike numbering = issues #69/#70/#71). UI polish items (S7.4 / #72, S7.5 / #73) were scoped on shape day from Sprint 6 carry-overs.

**Blockers + resolution:**
- `isolation: "worktree"` failed at session start with "not in a git repository" despite the working tree being a real git repo. Fallback: sequential dispatch (one agent at a time) per existing Skills.md rule. Cost ~30% wall-clock vs. parallel-with-isolation; underlying race was structurally impossible since only one agent ever touched the tree at a time.
- S7.3 first dispatch stalled on a per-account usage limit (~30s, zero work landed). Retried after limit reset; retry shipped cleanly on first CI. New Skills.md entry: "Sprint-1-agent usage-limit retry pattern."
- No CI saga. All 5 PRs green on first CI attempt (3m35s–6m10s).

**Epics state end-of-sprint:**
- E1 HealthKit read — **COMPLETE** (since Sprint 6).
- E2 Exercise + routines — **COMPLETE** (since Sprint 6); grouped-rendering polish landed S7.5.
- E3 CloudKit — **foundation landed.** Custom MethodChannel walking-skeleton + typed record CRUD + record zones all shipped. Spike's S7.4 (batch + conflict) → S7.7 (entitlement toggle) carry to Sprint 8+.
- E4 Watch — still blocked on E3 completion (spike's S7.5–S7.6 specifically: change feed + Drift↔CloudKit mappers).
- E5 Daily targets — kicked off in S6.1 (Sprint 6); no new work this sprint.

**Capacity read:** well-calibrated. 5 items in 3 sequential waves. No PR rolled CI more than once. Two new process learnings in Skills.md: `flutter analyze` exits non-zero on `info`-level lints; `dart format` reflows new code on first run (accept-and-commit). Both informed the Wave 2/3 subagent briefs at dispatch time, not retroactively.

**Founder-side post-merge work (unblocks device-verification):** register `iCloud.dev.techxtt.liftlogApp` container in Apple Developer portal + confirm iCloud capability in Xcode → Signing & Capabilities. Steps in `vault/05 Architecture/Runbooks.md` § "CloudKit container setup". CI doesn't require this; only on-device runs do.

---

## Sprint 6 — E1/E2 UI closeout + E5 kickoff + E3 spike (2026-04-24)

**Merges shipped**
- `892b8d9` S6.4 (#62/PR #65) HK signal tiles on Progress — Wave 1
- `735925e` S6.1 (#59/PR #66) Daily targets + remaining view, schema v4→v5 — Wave 2
- `2bb993b` S6.2 (#60/PR #67) Exercise canonical picker (built-in `Autocomplete<T>`, no new dep) — Wave 3
- `4e645e1` S6.3 (#61/PR #68) Routines UI + start-workout-from-routine — Wave 4

**Spike (not merged):** PR #64 `spike/cloudkit-e3-viability` closed. Empirical finding: `flutter_cloud_kit 0.0.3` unsuitable (Map<String,String> write surface, 8 missing P0 primitives, Swift scope bugs). **Decision: PIVOT to custom CloudKit MethodChannel** in Sprint 7 (~1400–1850 LoC, 21–32 dev-days estimated).

**Tests after:** 340/340.

**Schema:** v4 → v5 (additive: `daily_targets`). Backup path documented pre-code.

**Deps added:** none. Flutter's built-in `Autocomplete<T>` used for the exercise picker. `flutter_cloud_kit` evaluated on throwaway branch, rejected.

**Decisions recorded (Decision Log):**
- E3 deferred from Sprint 6 → Sprint 7 (spike first, then custom bridge).
- E3 plugin choice: PIVOT to custom MethodChannel bridge.
- Sprint 7 skeleton: 7 E3 issues + likely mix of UI polish items.

**Blockers + resolution:** Wave 1 parallel-dispatch race — two subagents shared the same git working tree; one's branch-switch clobbered the other's uncommitted edits (recovered, but avoidable). Skills.md updated with a rule requiring `isolation: "worktree"` on every future parallel dispatch.

**Epics state end-of-sprint:**
- E1 HealthKit read — **COMPLETE** (plumbing + UI).
- E2 Exercise + routines — **COMPLETE** (data + UI + start-from-routine flow).
- E3 CloudKit — research done; custom bridge queued for Sprint 7.
- E5 daily targets — kicked off (current-target + remaining view landed).

**Capacity read:** well-calibrated. 5 items (4 production + 1 spike) in 4 waves. One process correction recorded; Sprint 7 tests the `isolation: "worktree"` rule.

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
