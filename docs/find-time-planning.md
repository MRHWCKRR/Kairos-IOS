# Find a time and backlog planning

Schedule > Backlog lists unscheduled tasks, overdue dates/deadlines, elapsed-today placements and pending recurring occurrences. Locked rows are labelled; ordinary task manual scheduling remains available.

Suggestions use web planning models vendored from `bab63839209f2120ef2d9559c612c9d6105a6c1a`. The next 14 days use saved weekly availability (web 07:00–22:00 fallback), preferred time, five-minute candidates, session gaps, occupied events/tasks including completed work, DST-valid durations, deadlines and assignment daily-work limits. Recovery after a past deadline is labelled.

The preview shows prior placement and candidate times. After an uncertain save, the request identity and selected placement stay fixed. Retry checks the original receipt first. New writes revalidate saved settings, calendar occupancy, duration, target identity/location/status/lock, timezone and availability. Existing schedule receipts and guarded Undo are reused. Recurring changes retain their logical date. Only changed scheduling fields enter raw documents, preserving unknown metadata.

Backlog and preview calculations run away from the main actor and reject stale account/planner/revision results. Account/planner changes clear previews.

Node smoke checks cover suggestions, occupancy/settings conflicts, locks, elapsed-today/deadline recovery, assignment limits, unavailable days, Undo and recurring identity/focus metadata. A Swift bridge test covers preview/apply/Undo and metadata. CI runs smoke checks, Swift tests in three timezones, app/widget build and bundle checks. Manual device interaction remains separate.

No bulk planning, assignment authoring, destructive series edits or billing changes.
