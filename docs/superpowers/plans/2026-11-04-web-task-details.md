# Web task details

Use canonical web notes (3000 UTF-16 units), priority (low/medium/high/null), estimatedMinutes (1...1440/null), and checklist (100 items, stable IDs up to 120 units, nonempty titles up to 180 units). Preserve missing legacy fields and unknown metadata through the existing raw planner merge. Keep legacy descriptions visible as a fallback without silently migrating or overwriting them.

Add editors for notes, priority, estimates and checklist add/edit/complete/remove/move. Keep drafts on failure. Use field patches and per-item three-way checklist merge. Preserve a single device's reorder alongside concurrent additions/deletions; reject competing edits. Validate final checklist limits and recurrence rules again inside the Firestore transaction after merging.

Recurring template steps may be edited but must stay unchecked; no occurrence editor is added. Block direct and inherited series completion. Preserve complete recurrence definitions and exceptions in the raw document. Verify decode/round-trip/merge/limits/conflicts/recurrence via Swift package tests and compile the app and widget on macOS CI. Device UI testing remains required.