# LiftLog data export format (v1)

This is the authoritative spec for the JSON payload produced by **Export all data (JSON)** on the History tab (introduced in issue #37).

Scope: **user-entered rows only.** Derived values (daily kcal totals, weight deltas, weekly workout volumes, averages) are computed by the app at read time and are intentionally omitted — the trust guarantee is "I can keep a personal backup of my data", and that means the raw rows I typed, not numbers the app re-derives.

The format is designed to be machine-readable first. snake_case keys match the Drift column names; numbers are JSON numbers (not strings); timestamps are UTC ISO 8601 with millisecond precision; enums are the exact Dart `.name` string that Drift's `textEnum<T>()` stores in SQLite.

## JSON shape

```json
{
  "meta": {
    "format_version": "1",
    "app_version": "1.0.0+1",
    "schema_version": 4,
    "exported_at": "2026-04-24T09:14:00.000Z",
    "counts": {
      "food_entries": 42,
      "body_weight_logs": 18,
      "workout_sessions": 6,
      "exercise_sets": 71,
      "routines": 3,
      "routine_exercises": 12
    },
    "note": "All arrays below are user-entered rows exactly as stored. Daily totals, weight deltas, weekly workout volumes, and other summaries are derived by the app at read time and intentionally not included."
  },
  "food_entries": [
    {
      "id": 1,
      "timestamp": "2026-04-24T09:14:00.000Z",
      "name": "Eggs",
      "kcal": 140,
      "protein_g": 12.0,
      "meal_type": "breakfast",
      "entry_type": "manual",
      "note": null
    }
  ],
  "body_weight_logs": [
    {
      "id": 1,
      "timestamp": "2026-04-24T07:05:00.000Z",
      "value": 80.5,
      "unit": "kg"
    }
  ],
  "workout_sessions": [
    {
      "id": 1,
      "started_at": "2026-04-23T18:00:00.000Z",
      "ended_at": "2026-04-23T19:05:00.000Z",
      "note": null
    }
  ],
  "exercise_sets": [
    {
      "id": 1,
      "session_id": 1,
      "exercise_name": "Bench Press",
      "reps": 8,
      "weight": 80.0,
      "weight_unit": "kg",
      "status": "completed",
      "order_index": 0
    }
  ],
  "routines": [
    {
      "id": 1,
      "name": "Push A",
      "notes": null,
      "created_at": "2026-04-20T12:00:00.000Z",
      "source": "userEntered"
    }
  ],
  "routine_exercises": [
    {
      "id": 1,
      "routine_id": 1,
      "exercise_id": 4,
      "order_index": 0,
      "target_sets": 4,
      "target_reps": 8,
      "target_weight": 80.0,
      "target_weight_unit": "kg"
    }
  ]
}
```

## Field rules

- **snake_case keys** throughout — matches Drift column names and is the ergonomic pick for any Python/Ruby/Shell script reading this later.
- **Timestamps** serialize via `dt.toUtc().toIso8601String()` — always UTC, always millisecond precision, always the trailing `Z`.
- **Nullable timestamps** (`workout_sessions.ended_at` when a session is still in progress) serialize as JSON `null`. The key is always present; do not check with `"ended_at" in row` — check the value.
- **Enums** serialize as the exact Dart `.name` string (identical to the SQLite `textEnum` storage). See the [enum reference](#enum-reference) below. No remapping.
- **Numbers** are JSON numbers. `kcal`, `reps`, `order_index`, `id`, `session_id`, `schema_version` are integers; `protein_g`, `weight`, `value` are doubles. No locale formatting, no quoted numbers.
- **Array ordering**: every entity array is sorted by `id` ascending in Dart before serialization. Deterministic across runs: two consecutive exports of the same DB with the same `exported_at` produce byte-identical output.
- **No other keys.** Any future field requires a `format_version` bump and a matching spec update in this file.

### `routines`

Reusable workout templates (schema v4, issue #52). A routine is a named lineup of exercises a user can later spin up into a concrete `WorkoutSession`.

| Field | Type | Notes |
|---|---|---|
| `id` | int | Primary key. |
| `name` | string | Required. |
| `notes` | string \| null | Free-form; `null` serializes as JSON `null`. |
| `created_at` | ISO 8601 UTC string | Same timestamp convention as the other entities. |
| `source` | enum string | `Source.name`. See [enum reference](#enum-reference). |

### `routine_exercises`

Line items on a routine (schema v4, issue #52). Each row pairs a routine with an exercise and optional per-exercise targets.

| Field | Type | Notes |
|---|---|---|
| `id` | int | Primary key. |
| `routine_id` | int | FK → `routines.id`. `ON DELETE CASCADE`. |
| `exercise_id` | int | FK → `exercises.id`. The `exercises` catalog is not itself exported today (it's seeded from `exercise_sets.exercise_name`), so routine_exercises imports assume the destination DB already has the matching exercise row — same pattern as the `exercise_sets` → `workout_sessions` contract. |
| `order_index` | int | Authoritative ordering within the routine. |
| `target_sets` | int \| null | |
| `target_reps` | int \| null | |
| `target_weight` | double \| null | |
| `target_weight_unit` | enum string \| null | `WeightUnit.name`; `null` if the routine doesn't prescribe a weight (bodyweight or reps-only). |

## Enum reference

Every enum value is listed here. The serialized string is the Dart `.name`.

### `MealType`
| Value | Serialized |
|---|---|
| `MealType.breakfast` | `"breakfast"` |
| `MealType.lunch` | `"lunch"` |
| `MealType.dinner` | `"dinner"` |
| `MealType.snack` | `"snack"` |
| `MealType.other` | `"other"` |

### `FoodEntryType`
| Value | Serialized |
|---|---|
| `FoodEntryType.manual` | `"manual"` |
| `FoodEntryType.savedFood` | `"savedFood"` |
| `FoodEntryType.barcode` | `"barcode"` |
| `FoodEntryType.estimate` | `"estimate"` |

### `WorkoutSetStatus`
| Value | Serialized |
|---|---|
| `WorkoutSetStatus.planned` | `"planned"` |
| `WorkoutSetStatus.completed` | `"completed"` |
| `WorkoutSetStatus.skipped` | `"skipped"` |

### `WeightUnit`
| Value | Serialized |
|---|---|
| `WeightUnit.kg` | `"kg"` |
| `WeightUnit.lb` | `"lb"` |

### `Source`
| Value | Serialized |
|---|---|
| `Source.userEntered` | `"userEntered"` |
| `Source.savedTemplate` | `"savedTemplate"` |
| `Source.healthKit` | `"healthKit"` |
| `Source.photoEstimate` | `"photoEstimate"` |
| `Source.voiceEstimate` | `"voiceEstimate"` |
| `Source.barcode` | `"barcode"` |
| `Source.derived` | `"derived"` |
| `Source.imported` | `"imported"` |

## Not included

The export contains only the rows you typed. These **are** always in the app but **are not** in the export file:

- **Daily kcal / protein totals.** Derived from the food entries in the export — sum by day if you want them.
- **Weight deltas and moving averages.** Derived from `body_weight_logs`.
- **Weekly workout volume (completed sets per week).** Derived from `exercise_sets` filtered by `status == "completed"`.
- **Recent-foods quick-add list.** Derived from `food_entries`.
- **Session durations.** Derived from `started_at` and `ended_at`.

If any of those ever start appearing in the export, that's a regression — every key in this file is listed above.

## Stability

- `format_version` bumps **when a breaking shape change lands** — a removed entity, a renamed key, a changed serialization of an existing field, or any change that would make an older importer read the file wrong. **Additive snake_case keys do not require a bump:** old importers ignore unknown keys, new importers treat missing keys as empty / null. That's the rule that let the S5.1 `source` column addition and the S5.5 `routines` / `routine_exercises` sections both ship at `format_version: "1"`.
- `schema_version` tracks the Drift DB schema (`AppDatabase.schemaVersion`). It changes independently of `format_version`: a schema migration that doesn't surface new user-visible columns does not require a `format_version` bump.
- `app_version` is informational. It matches the `pubspec.yaml` version at build time.

## Delivery

The app writes the JSON to a file under the iOS temporary directory (via `path_provider`'s `getTemporaryDirectory`) and opens the system share sheet (`share_plus`'s `UIActivityViewController` wrapper). From there the founder picks Save to Files, email, or AirDrop — whatever destination they want. The app does not upload, sync, or retain a copy beyond the temp file iOS cleans up on its own cadence.

Filename template: `liftlog-export-<YYYYMMDDTHHMMSSZ>.json` — the timestamp is the export instant in UTC with `:` and `.` stripped for cross-filesystem safety.
