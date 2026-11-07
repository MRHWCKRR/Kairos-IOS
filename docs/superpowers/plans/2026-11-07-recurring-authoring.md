# Native recurring task authoring

Goal: create daily/weekly/monthly/yearly/custom recurring tasks and edit a single occurrence, this and future logical dates, or an entire series with a reviewed date sample.

Architecture: reuse the vendored recurrence utilities and web applyRecurringEdit operation. Swift owns raw-document transactions, immutable editor baselines, identity/location/account checks and metadata preservation. SwiftUI owns retained drafts and explicit preview/apply. Existing occurrence status/checklist editor remains available.

Constraints: no new dependencies, listeners, migrations or destructive series deletion. Completed, moved, skipped and progress-bearing occurrences retain their identities and progress. Never copy focus/remaining ledgers into a split series. Unknown task/rule/exception metadata stays raw. Conversion of completed, nested or assignment-linked tasks is rejected. Date pickers capture profile timezone. Save must match reviewed baseline and draft.

- [ ] Add failing model tests for scopes, count exhaustion, historical/moved/completed/checklist/focus preservation, invalid rules and preview purity.
- [ ] Add bounded native recurrence request adapter around shared web editing semantics, with date samples and strict input validation.
- [ ] Add Swift rule/request/baseline types and guarded raw-plan creation/edit mutations; test metadata, archive, identity, movement and stale snapshots.
- [ ] Add native repeat fields, new-task form, occurrence/series editor and reviewed Apply. Connect Boards task details and occurrence details without replacing parent drafts.
- [ ] Run all Node smoke suites, review changes, and run macOS Swift tests in three timezones plus iOS/widget build before merging to main.

Review focus: moved logical dates, split at first/final counted occurrence, pending progress not lost, stale preview/account switch, unknown Firestore metadata.
