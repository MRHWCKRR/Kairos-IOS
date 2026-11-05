# Native planning settings

Settings > Accessibility edits the web profile timezone, 12/24-hour time format, daily task work limit, session gap, weekly availability and completed-task rescheduling. The latter defaults off. Timezone and time format update native schedule/Today labels and date/time pickers; stored planner times remain 24-hour strings.

Storage uses the same web leaf paths: settings.profile.timezone, settings.accessibility.timeFormat, and settings.planning.{dailyLimitMinutes,gapMinutes,rescheduleCompleted,weeklyAvailability}. Daily limits are 0 (unlimited) or 15–1440; gaps are 0/5/10/15. Weekly hours are null (default 07:00–22:00), or a complete Sunday=0 through Saturday=6 map with up to four nonoverlapping same-day windows per day. Empty days are unavailable. Validation is vendored from the web normalizers; saved windows are sorted.

The editor holds a one-time account-scoped draft. Live changes, including invalid/unsupported settings, do not replace an open draft. Cancel and explicit Reload ask before discarding. Failed saves retain the form. Reload refreshes only the planning editor, preserving other app drafts. A verified-account Firestore transaction re-reads current settings, rejects conflicting edits to changed fields and writes only changed leaves. Other settings, unknown keys and concurrent changes to untouched fields remain intact. Exact retry values are accepted; late account callbacks cannot update another account. Only the authoritative listener restores post-save values so an old save response cannot rewind newer state.

These defaults sync with existing web Planning/AI workflows and the native completed-task rescheduling guard. They do not move existing tasks, mutate reviewed previews, or add the advanced native planning hub (still tracked in web-ios-parity.md).

Node smoke covers real web-compatible range/window validation. Swift tests cover native defaults, strict validation, field-level concurrent merges, exact retries, window normalization and display formatting. CI builds the app/widget and checks the bundled validator. Manual iPhone/simulator form, picker and sheet checks remain separate.
