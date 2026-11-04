# Reliable task mutations

Goal: one task command path, explicit partial edits, and retained drafts on failed saves.
Use the existing SwiftUI interface, Firebase transactions and unknown-field-preserving merge.

Implementation:
- Route create, edit, completion, archive and delete through a pure KairosTaskMutation command handler.
- Represent each editable field as unchanged or set(value), including set(nil) for clearing.
- Compare only edited fields with the editor's original task before applying to the current planner.
- Return Bool save results from repository mutations; fail missing targets explicitly.
- Keep task, board and creation/rename editors open on failure, disable duplicate submissions, and show errors beside retained drafts.
- Award completion credit only after persistence succeeds.
- Exercise partial edits, explicit clearing, stale drafts, deletion conflicts, duplicate IDs and parent cycles in Swift package tests.
- Verify the complete Swift test suite and unsigned app-and-widget build on macOS CI.

Limits: no offline write queue or new web-only task fields. UIKit/SwiftUI interaction validation still requires a simulator or device.