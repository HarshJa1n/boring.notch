# Reminders Tab — Implementation Plan (v2, three-column)

A third tab in the open-notch header (after **Home** and **Shelf**) that is a full
Apple Reminders client, driven entirely from the notch.

> **v2 changes:** three-column layout replaces the vertical list; tags/flags dropped;
> NL parsing scoped down to dates + recurrence; capture field is always-on with no `+` button.

---

## 0. What already exists (leverage, don't rebuild)

The repo already has a partial EventKit layer, built to surface reminders *inside the
calendar list*. We reuse the plumbing and build a real client on top.

| Existing | File | Reuse as |
|---|---|---|
| `EKEventStore` wrapper, `requestAccess(to:)`, `calendars()` | `boringNotch/Providers/CalendarServiceProviding.swift` | Base store; extend with reminder CRUD |
| `reminderLists` (`[CalendarModel]` filtered `isReminder`) | `boringNotch/managers/CalendarManager.swift` | List picker source |
| `checkReminderAuthorization()` | `CalendarManager.swift` | Permission gate |
| `setReminderCompleted(reminderID:completed:)` | `CalendarService` | Complete toggle |
| `ReminderToggle` (circle check control) | `boringNotch/components/Calendar/BoringCalendar.swift` | Extract & share |
| `.EKEventStoreChanged` observer | `CalendarManager.swift` | Two-way sync trigger |
| Tab registration | `boringNotch/components/Tabs/TabSelectionView.swift` | Add third `TabModel` |
| View switch | `boringNotch/ContentView.swift:381` | Add `case .reminders` |

### Blockers to clear first

1. **`NSRemindersFullAccessUsageDescription` is missing.** `project.pbxproj` sets only
   `INFOPLIST_KEY_NSRemindersUsageDescription`. The dev machine runs **macOS 27**, so
   `store.requestFullAccessToReminders()` is the only code path, and it **requires** the
   FullAccess key — without it the request fails and every write silently dies. Add
   `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` (plus
   `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`) to Debug **and** Release configs.
2. **`EventModel.init?(from: EKReminder)` returns `nil` when there's no due date.** A
   reminders client must show undated items. Needs its own model (§1).
3. **`CalendarService` owns a private `EKEventStore`.** The new service must share the *same*
   instance or completion toggles in one place won't invalidate the other's cached objects.
   Promote to `EventStoreProvider.shared.store`.

### Dropped from v1

- **Tags and flags.** Neither has a public EventKit API, and they're not a priority.
  Reminders created here go to a chosen list; that's the whole taxonomy. (If tags matter
  later, list-per-tag is the native route.)

---

## 1. Data layer

### `ReminderModel` — `boringNotch/models/ReminderModel.swift`

`EventModel` is event-shaped (demands `start`/`end`, drops undated items), so reminders get
their own struct:

```
struct ReminderModel: Identifiable, Equatable {
    let id: String                 // calendarItemIdentifier
    var title: String
    var notes: String?
    var dueDate: Date?             // nil == undated  (EventModel can't express this)
    var hasTime: Bool              // due has hour/min vs. day-only
    var isCompleted: Bool
    var priority: ReminderPriority // none/low/medium/high → EKReminder 0/9/5/1
    var list: CalendarModel
    var recurrence: RecurrenceSummary?
}
```

### `RemindersService` — `boringNotch/Providers/RemindersServiceProviding.swift`

```
protocol RemindersServiceProviding {
    func requestAccess() async throws -> Bool
    func lists() async -> [CalendarModel]
    func reminders(matching: ReminderQuery) async -> [ReminderModel]
    func create(_ draft: ReminderDraft) async throws -> ReminderModel
    func update(_ reminder: ReminderModel) async throws
    func setCompleted(id: String, completed: Bool) async throws
    func delete(id: String) async throws
}
```

- Backed by the shared `EKEventStore`.
- `ReminderQuery` = `{ lists: Set<String>, window: TimeWindow, includeCompleted: Bool }`.
- Fetch via `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)`, plus
  `predicateForCompletedReminders(...)` when completed are shown; union and sort.
- EventKit work stays off the main actor; results hop back to `@MainActor` to publish.

### `RemindersManager` — `boringNotch/managers/RemindersManager.swift`

`@MainActor ObservableObject`, shaped like `CalendarManager` so it reads as native here.

- `@Published`: `reminders`, `lists`, `authorizationStatus`, `isLoading`, `selectedID`.
- **Sync:** subscribes to `.EKEventStoreChanged`, debounced 300ms → refetch. That covers
  edits from Reminders.app, iPhone via iCloud, and Siri. Sync is two-way for free because we
  write through EventKit into the same store — there is no second copy of the data anywhere.
- **Optimistic updates:** completion toggles mutate the local array first, then write; on
  failure, revert and surface inline. EventKit saves run 100–300ms and the notch must feel
  instant.
- Derived slices for the columns: `focusItems` (overdue + today), `upcomingSections`
  (grouped by day, honoring the time window).

---

## 2. Natural-language parsing — **keeping it, scoped down**

`boringNotch/helpers/ReminderNLParser.swift` — pure, no EventKit, unit-testable.

Worth keeping because without it "call bank tomorrow 3pm" becomes a reminder *literally
titled that* with no due date, which defeats the type-and-go capture flow. Scoped down from
v1: **dates/times and recurrence only.** No tag or list-routing syntax.

Input: raw string → `ReminderDraft { title, dueDate, hasTime, recurrence, priority }`.

1. **Priority tokens:** `!` / `!!` / `!!!` → low / medium / high. Trivial, and worth having
   since priority is otherwise a two-click detour.
2. **Recurrence:** `every day|weekday|week|month|year`, `every mon/tue/…`, `every 2 weeks`,
   `daily|weekly|monthly`. → `EKRecurrenceRule`.
3. **Date/time:** `NSDataDetector(types: .date)` as the engine — built into Foundation,
   locale-aware, already handles "tomorrow at 3", "next friday", "in 2 hours", "jan 14".
   Post-process the gaps: `tonight` → 20:00, `morning` → 09:00, `noon`, `eod` → 17:00;
   `hasTime` from whether the detector reported time granularity; reject matches spanning
   the whole string (that's a title, not a date).
4. **Remainder = title**, whitespace-collapsed.

`NSDataDetector` over a hand-rolled grammar deliberately: no third-party dep, handles the
long tail of phrasings, keeps the binary light for an always-resident menu-bar app. Realistic
size is ~150 lines plus tests.

**Live feedback** is what makes it safe — see column 3 below. Nothing commits until Return,
and the user always sees the interpretation first.

---

## 3. UI — three columns

### Why columns

Open notch is **640 × 190** (`openNotchSize`, `boringNotch/sizing/matters.swift`), minus
~12pt horizontal padding and a ~26pt header → roughly **616 × 150 usable**. That is a wide,
short letterbox. A vertical list wastes it and caps out at 4–5 rows. Three columns turn the
same space into ~200pt each with a full-height list in each — far better use of the aspect
ratio, and it means the capture field never competes with the list for vertical room.

```
┌──────────────────┬──────────────────┬─────────────────────┐
│ TODAY         3  │ UPCOMING         │ ┌─────────────────┐ │
│ ◯ Ship build     │ Thu              │ │ Type a reminder…│ │ ← always focused
│   overdue    !!  │ ◯ Water plants   │ └─────────────────┘ │
│ ◯ Call bank      │ ◯ Renew domain   │  Tomorrow 3:00 PM   │ ← live parse chips
│   4:30 PM        │ Fri              │  Work · !!          │
│ ◯ Review PR      │ ◯ Standup   9 AM │ ─────────────────── │
│ ● Buy milk       │ Sat              │  (idle → inspector  │
│   (faded)        │ ◯ Groceries      │   for selected row) │
└──────────────────┴──────────────────┴─────────────────────┘
   ~200pt              ~200pt               ~216pt
```

**Column 1 — Focus.** Overdue + today, the stuff that actually matters now. Count badge in
the header. Scrolls independently.

**Column 2 — Upcoming.** The configurable horizon (§4), grouped by day with sticky day
headers. Scrolls independently. This is the "show more" column.

**Column 3 — Capture + Inspector.**
- **Top: the text field.** Always visible, auto-focused when the tab opens. Type, press
  Return, it appends and clears — exactly the Reminders.app behavior, **no `+` button
  anywhere**. `⌘↩` commits and keeps focus for rapid-fire entry.
- **While typing:** parse chips render directly below (`Tomorrow 3:00 PM` · `Work` · `!!`).
  Dimmed chip = low-confidence parse, click to correct.
- **While idle:** the same area becomes the inspector for whichever row is selected in
  column 1 or 2 — title, due, priority, recurrence, list, notes. Editing happens here, in a
  column that already exists, so **no sheets, no in-place row expansion, no reflow.** This is
  the main structural win over v1.

### Components — `boringNotch/components/Reminders/Views/`

- `RemindersView` — the three-column `HStack`, owns selection state.
- `ReminderColumn` — generic column shell (header + scrolling `LazyVStack`), used by 1 and 2.
- `ReminderRow` — 26pt row: toggle · title · trailing meta (relative due, priority dots,
  list color bar). Reuses the extracted `ReminderToggle`. Click selects (drives column 3);
  the toggle completes; context menu for delete.
- `ReminderCaptureField` — the always-on input.
- `ReminderParsePreview` — the chip row.
- `ReminderInspector` — the idle-state editor.
- `RemindersEmptyState` / `RemindersPermissionPrompt` — mirroring `EmptyEventsView`'s tone;
  permission button opens
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders`.

### Consistency

- Colors come only from the existing palette (`.white`, `Color(white: 0.65)`,
  `CalendarModel.color`). No new constants, so it can't drift from Home/Shelf.
- Row height, corner radii, font ramp (`.callout` title / `.caption` meta) copied from
  `EventListView` — the Reminders tab and the Home calendar should look like one app.
- Animations from `StandardAnimations`, never ad-hoc `.easeInOut`.
- Column dividers: 1pt `Color(white: 0.18)`, matching existing separator weight.

### Keyboard

The notch is a hover target — the mouse is busy getting there, so keyboard has to be real.
`↑`/`↓` move selection within a column, `←`/`→` switch columns, `Space` toggles complete,
`⌫` deletes with an undo toast, `⌘F` jumps to capture, `Esc` closes the notch.

### Lightweight

- `LazyVStack` in `ScrollView`, not `List` — avoids `NSTableView` overhead in a 150pt
  viewport, and matches how `ShelfView` renders.
- Fetches debounced, only when the tab is visible or the store changes. No timers.
- Parser is pure string work; regexes compiled once as `static let`, not per keystroke.
- Nothing in this feature runs while the notch is closed.

---

## 4. Settings

New `RemindersSettingsView.swift`, registered in `SettingsView.swift`
(`Label("Reminders", systemImage: "checklist")`). New keys in `Constants.swift`:

```
static let enableRemindersTab        = Key<Bool>("enableRemindersTab", default: true)
static let reminderTimeWindow        = Key<ReminderTimeWindow>(..., default: .thisWeek)
static let reminderListSelection     = Key<CalendarSelectionState>(...)  // reuse existing type
static let defaultReminderList       = Key<String?>("defaultReminderList", default: nil)
static let showCompletedReminders    = Key<Bool>("showCompletedReminders", default: false)
static let remindersDefaultTime      = Key<Int>("remindersDefaultTime", default: 9)
static let openRemindersTabByDefault = Key<Bool>(..., default: false)
```

`ReminderTimeWindow`: `today | tomorrow | next3Days | thisWeek | next2Weeks | month | all`,
plus `custom(days:)` exposed in Settings. Drives column 2's horizon.

Settings content: enable/disable tab · which lists to show & default list for new items ·
time window · show completed · default time-of-day · natural-language syntax cheat sheet.

---

## 5. Wiring

1. `NotchViews` (`boringNotch/enums/generic.swift`) → add `case reminders`.
2. `TabSelectionView.swift` → `tabs` is a `let` global today; make it computed so the third
   tab can be conditional on `Defaults[.enableRemindersTab]`.
   `TabModel(label: "Reminders", icon: "checklist", view: .reminders)`.
3. **`BoringHeader.swift:15`** → the tab strip only renders when
   `(!tvm.isEmpty || alwaysShowTabs) && Defaults[.boringShelf]`. That hides tabs entirely
   when the shelf is off, which would make Reminders unreachable. Widen to
   `(shelfEligible && Defaults[.boringShelf]) || Defaults[.enableRemindersTab]`.
4. `ContentView.swift:381` → `case .reminders: RemindersView()`.
5. **Notch must not auto-close while typing.** `ContentView`'s hover-out logic will dismiss
   the notch mid-sentence. Reuse the existing `SharingStateManager.preventNotchClose` hatch —
   the same pattern the share sheet already uses — held while the capture field is focused or
   the inspector is being edited. Release it on blur so normal hover-out resumes.
6. `BoringViewCoordinator` → include `.reminders` in last-tab restore; make sure
   `showEmpty()` / `.home` fallbacks don't strand the user on a disabled tab.
7. `ShortcutConstants.swift` → "Open notch to Reminders", and a global **"Quick add
   reminder"** that opens the notch with the field focused. Highest-value entry point in the
   whole feature: capture without touching the mouse.
8. `project.pbxproj` → the two FullAccess usage-description keys (§0).
9. Localization strings into the existing catalog, matching `EmptyEventsView` / OSD settings.

---

## 6. Build order

| # | Step | Why here |
|---|---|---|
| 1 | Info.plist FullAccess keys + shared `EKEventStore` + `RemindersService` read path | Nothing works without access; proves the data layer |
| 2 | `ReminderModel`, `RemindersManager`, `.EKEventStoreChanged` sync | The sync requirement, isolated and verifiable |
| 3 | Tab wiring (incl. `BoringHeader` fix) + columns 1 & 2, read-only | Something visible end-to-end |
| 4 | Complete-toggle + optimistic update + selection | First write path; validates the whole write stack |
| 5 | `ReminderNLParser` + unit tests | Pure, testable, zero UI risk |
| 6 | Column 3 capture field + parse chips + create + `preventNotchClose` | The headline flow, on a proven foundation |
| 7 | Inspector (due / priority / recurrence / list / notes) | Largest UI surface, lowest risk once 4 and 6 work |
| 8 | Settings pane + time window + shortcuts | Configuration, once behavior is settled |
| 9 | Keyboard nav, empty/permission states, polish | Final layer |

Steps 1–4 are a useful tab on their own; everything after is additive.

---

## 7. Open items

- **190pt is the hard ceiling.** The column design bends around it. If Reminders later wants
  more room, `openNotchSize` is a global — per-tab height would mean reworking
  `BoringViewModel` sizing and should be its own piece of work.
- **Sandbox:** `com.apple.security.personal-information.calendars` is already in
  `boringNotch.entitlements` and covers EventKit reminders. No new entitlement expected, but
  verify on the first signed build — TCC failures here are silent.
- **Column 3 dual-purpose** (capture while typing, inspector while idle) is the one piece
  worth watching in use. If the mode-switch feels jumpy, the fallback is a fixed capture
  field with the inspector below it in the same column, at the cost of ~30pt.
