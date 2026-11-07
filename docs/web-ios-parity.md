# Web and iOS capability parity

Audit: 5 November 2026. Compared web `a9c443ce43e5da3e62b869df7f80918b3e91d882` with iOS `07fb1b0fd781d8946752c3d324566e68a86eac37`, then implemented the first bounded parity batch below. This is a source/reachable-UI audit, not a claim of device interaction testing or complete parity. `MainTabView` uses `TasksWorkspaceView`, `CalendarView` and `AIHelperView`; functionality present only in unused legacy views does not count.

## First parity batch

| Area | Change |
| --- | --- |
| Home | Replaces the five-item Up next sample with the web Today groups: Needs attention, On today, To plan; five initial rows per group and Show more; new task, details, manual Schedule, Plan today and ordinary completion. |
| Today semantics | Reuses web `today-model.js` grouping/order and existing recurrence/event engines. Missed scheduled dates or past deadlines need attention; dates use the profile timezone. Search uses its separate deadline-precedence rule; the two workflows intentionally follow their respective web models. |
| Recurring/events | Today shows pending historical/moved recurring logical dates and today's fixed/imported/overnight event segments. Opens the existing occurrence/event editor with the correct identity. Series templates are never completed from Today or Boards. |
| Board management | Current Boards menus reach edit board, rename section and reversible archive for boards/sections/tasks. Archive browser restores parents before individually archived children. Existing mutation transactions retain unknown web metadata. |
| Data safety | Owner/revision/day/timezone-scoped background Today projection; cancelled work cannot replace current results. Actions recheck identities and use guarded existing writes. Board description/name edits preserve unchanged remote fields and reject conflicting changed fields. |

## Planning settings follow-up (6 November 2026)

Settings > Accessibility now edits timezone, 12/24-hour display, daily task work limit, session gaps, all seven days of weekly availability, and completed-task rescheduling (default off). Saves use the web fields with changed-leaf transaction guards and retained drafts. Native display labels/pickers follow the chosen clock format and profile timezone; stored schedule times and existing tasks are unchanged. See [planning-settings.md](planning-settings.md). Advanced native planning workflows remain in the backlog below.

## Task editor follow-up (6 November 2026)

Task details now edit reminder timing, AI scheduling lock and preferred time using the shared web fields. Assignment/session links show web-compatible progress, remaining estimates, deadlines and readiness, with navigation between linked tasks. Saves retain drafts and reject conflicting edits, archived targets and moved tasks. See [task-editor-parity.md](task-editor-parity.md).

## Recurring authoring follow-up (7 November 2026)

New task > Repeat and task/occurrence details > Edit repeat now reach native rule authoring. The editor previews up to four affected dates before Apply, defaults to a single occurrence when opened from one, and preserves historical, individually moved and progress-bearing occurrences across splits. No destructive series removal is exposed. See [recurring-authoring.md](recurring-authoring.md).

## Task-linked focus follow-up (7 November 2026)

Task details and dated recurring occurrences now start a shared native focus session. Account-scoped recovery retains checkpoints and immutable pending requests. Logging uses shared web receipt/history semantics and updates the exact task or logical occurrence ledger with account totals in one transaction. Statistics adds a lifetime current-planner breakdown by board, assignment and task with estimate comparisons. Corrections, manual entries, explicit completion and remaining-work check-ins remain separate follow-ups. See [task-linked-focus.md](task-linked-focus.md).

## Find a time follow-up (8 November 2026)

Schedule > Backlog now reaches web-compatible slot suggestions with preview, guarded Apply/exact retry and Undo. Backlog includes recurring and elapsed-today work; suggestions respect saved availability, conflicts, gaps, deadlines, locks and assignment daily limits. See [find-time-planning.md](find-time-planning.md).

## Verified native equivalents already present

- Task/board/section creation; task notes, priority, estimates, checklists, scheduled times and deadlines; native subtasks.
- Global search with status filters and draft-preserving editors; recurring logical-date results.
- Day/3-day/week/month Schedule, agenda, filters, manual backlog scheduling, basic events, occurrence checklist/status/time editing, touch move/resize with snapping/retry/Undo.
- AI chat/project CRUD, shared project context, basic task/event/occurrence actions with durable native review/apply/discard. Pending web action batches are preserved and blocked with instructions, not silently consumed.
- Local task/bedtime notifications, shared notification preferences, reduce motion, theme/mode/fonts/text/background URL rendering, individual event export to Apple Calendar.
- General/task/occurrence focus timer and Live Activity, durable recovery/exact retries, aggregate statistics and lifetime planner breakdown. Native focus-history editing remains a gap.

## Remaining work, in dependency order

| Priority | Capability gap | Evidence / implementation scope |
| --- | --- | --- |
| 1 | Remaining task properties and assignment authoring | Web `task-detail-pane.js`, `task-actions.js`; native still lacks assignment/session creation, color/deadline-impact controls and move/reorder/duplicate/multiselect/bulk. Assignment/session progress is now readable; native parentTaskID subtasks remain distinct from web assignmentId sessions. |
| 2 | Remaining recurring workflows | Native now authors daily/weekly/monthly/yearly/custom rules and reviews occurrence/future/series edits. Destructive scoped deletion and disabling existing series remain separate follow-ups. |
| 2 | Remaining focus workflows | Native supports attribution, recovery, exact retries and lifetime reporting using web-compatible ledgers/history. Remaining work: recent-history corrections/removal, manual entries, explicit Log and complete, and remaining-work check-ins. |
| 1 | Planning hub / schedule AI | Web `planning-hub.js`, `schedule-ai.js`, `schedule-day-change-ui.js`; native lacks deadline/assignment/session/combined/conflict/review workflows, Plan schedule and My day changed proposals. Basic chat plan creation is distinct. |
| Done | Find a time / complete backlog | Native backlog now includes suggestions, overdue/elapsed-today recovery and recurring logical dates, with reviewed Apply and Undo. |
| 1 | Calendar import / conflict repair | Web `calendar-import.js`, `calendar-conflict-review.js`; native renders imported read-only events but has no file/feed/source manager or reviewed conflict repair. |
| 1 | Account data export / deletion | Web account export/deletion in `app.js`; native lacks account privacy actions. Requires verified reauthentication and coordinated user/planner deletion, separate from reversible UI work. |
| 2 | AI action/context completeness | Web `ai-action-schema.js`, `ai-workspace.js`; missing plan_* workflows, relocation/archive coverage, advanced event args, confirmed-target follow-ups, AI Undo, memory editing/summary generation/sibling summaries and native continuation of web-pending batches. |
| 2 | Advanced events / Schedule information | Web supports all-day/free/reminder and fortnightly/ranged rules/restoration, deadline markers and fixed-conflict labels. Native forms/basic event actions and timeline omit these. |
| 2 | Bulk calendar export | Web `calendar-export-view.js`; Apple single-event export does not cover reviewed task/event date-range .ics snapshots. |
| 2 | Notification inbox / completion wiring | Web `notification-center.js`; native has preferences/permissions but no saved inbox/read/delete UI. Board-completion delivery remains wired only in unused TasksView. |
| 2 | Archive permanent removal | The new native Archive supports reversible restore. Web archive management also exposes permanent removal; that destructive workflow remains separate from this batch. |
| 2 | Profile/security/accessibility | Editable profile/avatar/birthday, provider/last-sign-in and reauthenticated security controls; functional language/density options. Browser-specific shortcuts/device/session behavior should use native equivalents where appropriate. |
| 3 | Organization / media polish | Section collapse/focus/completed preferences; chat ordering/status/project icons/colors, richer markdown; image upload and working native ambient media. Visual differences alone do not imply missing capabilities. |

## Validation and practical boundary

Node Today smoke checks run the real vendored model and engines: missed schedules/deadlines, event order, historical/moved occurrence identity, skipped/completed exclusions, duplicates and no input writes. Swift tests exercise the native Today bridge and board mutation guards/parent-first archive behavior. CI also runs the existing core suite in UTC, Australia/Brisbane and America/New_York, builds the iOS app/widget, and verifies bundled engines. Native sheet/menu/touch interaction remains a separate manual simulator/device check.

This batch adds no cloud listeners, collection migrations, destructive removal, billing changes or focus-ledger writes.


