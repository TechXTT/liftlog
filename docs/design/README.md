# LiftLog — Design reference

Codifies the visual and copy contract of the app. Derived from a Claude Design handoff (2026-04-24) that extracted the system from the Flutter source + `CLAUDE.md`. The system is **what the app already is**, written down so future changes stay coherent without adding design bureaucracy.

When implementing a UI change, check this file. When a rule in here and `CLAUDE.md` disagree, `CLAUDE.md` wins — that's the founder-curated contract.

## Visual foundations

- **Seed color:** `Colors.deepPurple` (`#673AB7`). Every other color is an M3 tone derived from this seed. Rendered primary is `#65558F`.
- **Theme flags:** `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`, `useMaterial3: true`. No custom theme overrides anywhere in `lib/`.
- **Dark mode:** not implemented. `MaterialApp` declares no `darkTheme`. Adding one is a founder call.
- **Background:** `#FEF7FF` (M3 `surface`) — near-white with a purple whisper.
- **Dividers:** `#CAC4D0` (`outlineVariant`), 1px hairline. Separate rows, separate header from body.
- **Destructive reds (two, not interchangeable):**
  - `Colors.red` (`#F44336`) — `TextButton.foregroundColor` for "Delete entry" actions. Warning-lamp red.
  - `colorScheme.error` (`#B3261E`) — M3 error states (form validation). Deeper.
- **Estimate badge:** `secondaryContainer` / `onSecondaryContainer` (muted mauve on pale lilac). Never red, never yellow. Radius 4.
- **Typography:** Material 3 2021 scale, verbatim. SF Pro on iOS (platform default); no custom font.
- **Weights used:** 400, 500, 600 only. No bold display, no italics.
- **Spacing unit:** 4px. Screen gutter 16px. Empty-state block 24px. Field rhythm 12px. Touch targets ≥ 44pt.
- **Radii:** 4 (badge), 8 (mixed-units banner), 12 (cards / text fields), 16 (segmented / extended FAB), 28 (FAB).
- **No imagery, no gradients, no inner shadows, no neumorphism, no glass.** This is a data app.
- **Layout primary:** `ListView.separated` with `Divider(height: 1)`. No cards around list items.
- **Motion:** all Flutter Material defaults. `short ~150ms`, `medium ~250ms`, `long ~400ms`. Standard easing.

## Iconography

- **Library:** Material Icons (`Icons.*`), shipped with Flutter. No custom SVGs, no emoji.
- **Nav pattern:** outlined for inactive (`Icons.restaurant_outlined`), filled for active (`Icons.restaurant`). In-content icons use the filled / neutral variant.
- **No emoji anywhere** — not in labels, not in empty states, not in errors.
- **One Unicode exception:** the **middle dot `·` (U+00B7)** as the segment separator in summary rows (`Breakfast · 420 kcal · 28 g protein`). Always space-padded on both sides.
- **No arrows, chevrons, decorative glyphs.** `ListTile` chevrons are suppressed.

| Usage | Icon pair |
|---|---|
| Food tab | `restaurant_outlined` / `restaurant` |
| Weight tab | `monitor_weight_outlined` / `monitor_weight` |
| Workouts tab | `fitness_center_outlined` / `fitness_center` |
| History tab | `history_outlined` / `history` |
| Progress tab | `show_chart_outlined` / `show_chart` |
| Add | `add` (FAB) |
| Delete | `delete_outline` |
| Date+time | `edit_calendar_outlined` |

## Content fundamentals

**Voice:** plain, direct, functional. Founder talking to self. Not marketing copy, not coaching copy.

- **Sentence case everywhere.** `Add food`, not `Add Food`. `Body weight`, not `Body Weight`. Only proper nouns (meal names) capitalize: `Breakfast`, `Lunch`.
- **Active, imperative.** `Tap + to log your first one.`, `Pick a date & time`, `Start workout`.
- **Second person only when instructing.** Never first-person.
- **Contractions allowed** (`can't`, `cannot`). Consistent within a surface.
- **No emoji. Ever.**
- **No exclamation marks.**
- **Numbers + units go through `lib/ui/formatters.dart`.** Never hand-roll `'$x kcal'`.

### Pattern recipes

**Empty states** — two lines: what's missing + one-sentence next action.
> No entries yet today.
> Tap + to log your first one.

**Section headers** — plain noun phrases, no colons. `Body weight`, `Daily kcal`, `Past food days`.

**Totals / metrics rows** — middle-dot separator, space-padded.
> `Breakfast · 420 kcal · 28 g protein`
> `10 reps · 80 kg · Completed`
> `Started 09:14 · ended 10:02`

**Destructive confirms** — title as question, body explains consequence, **always ends with "This cannot be undone."**
> **Delete entry?**
> Delete "Oatmeal & berries" (320 kcal)? This cannot be undone.

**Errors** — log-line style, not an apology. No fabrication.
> `Could not load entries: $err`
> `Could not start workout: $err`
> `Totals unavailable: $err`

**Trust labels** — estimates always flagged via the `Est.` badge. Toggle copy:
> This is an estimate
> Tag entries you eyeballed so totals stay honest.

**Date & time formats**
- Header: `Today, Apr 24` (via `shortDate` — `Mon D`)
- Timestamp field display: `2026-04-24 09:14` (ISO-ish, zero-padded)
- Time-only (trailing cell): `09:14`

**Validation messages** — single short sentence, no trailing period.
> `Name is required`, `Enter a whole number`, `Must be zero or more`, `Time cannot be more than 1 hour in the future`, `Pick a date & time`

### Forbidden vocabulary (from `CLAUDE.md` trust rules)

- Any health or medical claim (`healthy`, `lose weight fast`, `burn fat`, `recommended intake`).
- Coaching language (`Great job!`, `You crushed it`, `keep going`).
- Anything implying a cloud / account (`sync`, `your account`, `share`).
- Anything implying the app "adjusted" a value (`we updated your goal`, `auto-corrected`).

## Assets

- `assets/liftlog-mark.svg` — 64×64 squircle, draft barbell glyph on primary purple. **Draft — not the app icon yet.**
- `assets/liftlog-wordmark.svg` — 280×64 horizontal lockup. **Draft.**
- The shipped app icon is still the default Flutter "F" placeholder. Replacement is a founder decision (tracked as a separate GitHub issue).

## Tokens reference

`tokens.css` in this directory holds the full M3 CSS variable set (colors, type scale, spacing, radii, elevation, motion). Useful if a design-side preview ever needs them; the Flutter app reads these values from `ThemeData` at runtime, not from CSS.

## Not in scope

- Dark mode tokens (app doesn't declare `darkTheme`).
- Marketing copy / brand guide / Figma file.
- Component library (Flutter's Material 3 is the library).
- Settings / onboarding / auth screens (the app has none).
- Android / Apple Watch chrome.

## See also

- [`../export-format.md`](../export-format.md) — authoritative JSON shape for the Export all data flow on the History tab.
