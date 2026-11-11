# Native assignment sessions

Task details > Break into sessions accepts total effort, minutes per session, optional titles and numbered order for an unfinished, unlocked, unscheduled task. The web planning model previews every placement using saved weekly availability, gaps, daily assignment limit, occupied time and deadline. If the full batch cannot fit, nothing is written.

Apply checks the reviewed plan and saved settings in a Firestore transaction, then creates every linked session task in the parent's section. The parent task and unknown metadata stay intact. The request and session IDs remain fixed after an uncertain save; a receipt confirms exact retries without duplicates. Guarded Undo archives created sessions while preserving later content changes and rejecting changed completion/scheduling state. Assignment progress and standard task editors show the resulting tasks.

Task details > Revise sessions accepts remaining effort for an assignment with linked sessions. It previews resized and rescheduled unfinished sessions, any new sessions, and surplus sessions that will be archived. Completed sessions remain intact. Apply and Undo use the same reviewed transaction and receipt path, updating only changed scheduling fields so notes, focus history, and unknown metadata survive.

Focused checks cover preview, conflicts, settings, metadata, Undo and completed-session rejection. CI also runs Swift tests in three timezones, app/widget build, bundled-engine and toolbar checks. Manual device interaction remains to verify separately.

Broader Planning hub workflows remain later work.
