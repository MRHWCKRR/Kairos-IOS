# Recurring occurrence display and status

First pass: show recurring occurrences in Calendar and complete, skip or reopen one occurrence. Rule editing and occurrence checklist editing remain subsequent work.

Bundle the existing web recurrence-utils engine using JavaScriptCore, with only an export/structuredClone adapter. Swift projects known JSON inputs without serializing unknown Firestore metadata. Support daily/weekly/monthly/yearly rules, count/date endings, historical and moved exceptions. Bound projection to 200 years from start and 10000 exceptions, reporting an error beyond that range.

Use logical seriesId::date identity independently of moved display dates. Native status writes run inside Firestore transactions, validate current account, ownership, unique target, archive state and engine-input revision, and only patch one exception in the current server task. Preserve rule fields, templates, unknown metadata, focus ledgers and other occurrences. Reopen historical occurrences with the web engine's schedule pin behavior.

Calendar observes a snapshot revision because the existing typed recurrence marker omits exception details. Exclude recurring templates from ordinary dated rows. Show pending/completed/skipped rows with errors and duplicate-save protection. Verify date/exception/status/conflict preservation tests across UTC, Brisbane and New York, then compile the app and widget and verify the JS engine exists in the app bundle.