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

## Verified native equivalents already present

- Task/board/section creation; task notes, priority, estimates, checklists, scheduled times and deadlines; native subtasks.
- Global search with status filters and draft-preserving editors; recurring logical-date results.
- Day/3-day/week/month Schedule, agenda, filters, manual backlog scheduling, basic events, occurrence checklist/status/time editing, touch move/resize with snapping/retry/Undo.
- AI chat/project CRUD, shared project context, basic task/event/occurrence actions with durable native review/apply/discard. Pending web action batches are preserved and blocked with instructions, not silently consumed.
- Local task/bedtime notifications, shared notification preferences, reduce motion, theme/mode/fonts/text/background URL rendering, individual event export to Apple Calendar.
- General focus timer/Live Activity, aggregate statistics and achievement views. These are partial equivalents, not task-linked focus or focus-history parity.

## Remaining work, in dependency order

| Priority | Capability gap | Evidence / implementation scope |
| --- | --- | --- |
| 1 | Complete task properties and assignments | Web `task-detail-pane.js`, `assignment-progress.js`, `task-actions.js`; native lacks reminder/AI-lock/scheduling-preference controls, assignment/session progress and move/reorder/duplicate/multiselect/bulk. Native parentTaskID subtasks are not web assignmentId sessions. |
| 1 | Recurring rule creation/editing | Web `schedule-recurrence-ui.js`, `schedule-inspector.js`; native supports occurrence edits but not authoring rules or this-and-future/entire-series scopes. Requires split/ledger preservation tests. |
| 1 | Task-linked focus, recovery and reporting | Web `focus-model.js`, `focus-store.js`, `focus-history-model.js`, `manual-focus-model.js`, `focus-breakdown-model.js`, `docs/task-focus.md`; native timer logs overall totals only, with no task/occurrence attribution, durable pending logs, corrections/manual entries or lifetime breakdown. Must reuse atomic receipt/history semantics before exposing these writes. |
| 1 | Planning hub / schedule AI | Web `planning-hub.js`, `schedule-ai.js`, `schedule-day-change-ui.js`; native lacks deadline/assignment/session/combined/conflict/review workflows, Plan schedule and My day changed proposals. Basic chat plan creation is distinct. |
| 1 | Find a time / complete backlog | Web `schedule-find-time.js`, `schedule-overdue.js`; native backlog/manual sheet lacks suggested slots, elapsed-today recovery and full recurring/deadline backlog. |
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
