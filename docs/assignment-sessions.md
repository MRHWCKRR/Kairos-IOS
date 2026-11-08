# Native assignment sessions

Task details > Break into sessions accepts total effort, minutes per session, optional titles and numbered order for an unfinished, unlocked, unscheduled task. The web planning model previews every placement using saved weekly availability, gaps, daily assignment limit, occupied time and deadline. If the full batch cannot fit, nothing is written.

Apply checks the reviewed plan and saved settings in a Firestore transaction, then creates every linked session task in the parent's section. The parent task and unknown metadata stay intact. The request and session IDs remain fixed after an uncertain save; a receipt confirms exact retries without duplicates. Guarded Undo archives created sessions while preserving later content changes and rejecting changed completion/scheduling state. Assignment progress and standard task editors show the resulting tasks.

Focused checks cover preview, conflicts, settings, metadata, Undo and completed-session rejection. CI also runs Swift tests in three timezones, app/widget build, bundled-engine and toolbar checks. Manual device interaction remains to verify separately.

Existing-session revision and broader Planning hub workflows remain later work.
