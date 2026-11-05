# Mobile web workspace parity

The web Schedule and AI workspace are the product reference. Keep native SwiftUI and adapt sidebars to sheets, inspectors to detail sheets, and dense timelines to horizontally scrollable day columns. Do not embed the desktop web app or change its mobile download gate.

Schedule: Day, 3 days, Week, Month with a shared date cursor; Today and date navigation; timed tasks using startTime/endTime (independent of dueTime); backlog and scheduled flexible tasks; task creation/editing/completion and rescheduling; recurring occurrence details; actual date-specific fixed events; daily insights. Preserve raw event exceptions and task metadata. Apple Calendar remains explicit export.

AI: users/{uid}.aiWorkspace version 2, shared chats/projects/messages and legacy aiChatHistory migration only when no workspace exists. Native chat list/project pages, new/rename/delete/move chats, shared project context, full-height conversations and a keyboard-following composer. Independent pending requests and drafts per chat; switching chats must not redirect a reply. Transactional edits preserve unknown web memory/action metadata. Invalid/newer data is read-protected rather than replaced.

Use existing verified Firebase sessions, App Check, AI relay, and planner transactions. Do not claim an AI action was applied when it was not. Keep reviewed plan generation while broader structured web action support is assessed. Document any remaining parity gaps explicitly.

Native chat now previews and atomically applies ordinary task, board, and section create/update/delete actions, including task scheduling and completion. Fixed event and recurring occurrence edits are available directly in Schedule. Chat requests for reminders, recurring series changes, fixed-event actions, and automatic multi-assignment planning explicitly direct users to the web; these advanced action adapters are not part of this implementation. Native proposals are session-local and must be requested again after restarting the app. Existing web pending-action receipts are preserved and protected from competing native requests.

The timeline uses touch-friendly sheets for moving/resizing. Desktop pointer dragging, resize handles, planning conflict repair, calendar import/feed management, and automatic memory summarisation remain web capabilities. Existing summaries and project context are read without discarding their web metadata; disabled automatic chat memory is respected.

Manual review on an authenticated iPhone simulator remains necessary for keyboard layout, Dynamic Type, and live cross-device editing. The available connected device is Windows; CI supplies the unsigned iOS build and core tests.

Verification: core model round trips, scheduling patches/conflicts, event projection including exceptions/overnight, workspace migration and concurrent operations, app build and all core tests in CI. This is a larger redesign: leave PR ready for review without merging.
