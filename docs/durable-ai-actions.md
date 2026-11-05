# Durable reviewed AI actions

Extend the existing native chat review flow. Keep the shared web action names/fields for events and task reminders; add an explicit occurrence action with taskId and original occurrenceDate. Recurring series are never silently changed by a request for one occurrence.

Persist versioned previews per chat under users/{uid}.aiNativeProposals. The web only writes aiWorkspace, so web normalisation cannot discard native previews. Each preview pins owner, chat, plan, timezone, proposal identity, planner fingerprint, and validated action payloads. Save the assistant reply and preview together. Read errors/newer versions remain visible and block replacement rather than silently deleting pending work.

Apply reads the user and planner together and checks the saved preview, current account, plan/timezone and reviewed fingerprint. All mutations, a bounded native receipt, the successful assistant message, and removal of the preview commit in one Firestore transaction. A retry checks its receipt before applying anything. Stale previews remain reviewable/discardable and cannot be applied to a different planner state. No provider request is needed to restore or apply a preview after launch.

Use the existing task mutations, raw merge, event mutation, and recurring occurrence engine. New actions: fixed event create/update/delete, task reminder set/remove, single recurring occurrence move/resize/status. Preserve unknown planner metadata. Preview rows show actual target names and before/after date/time/reminder/status, and clearly label destructive changes and notification delivery state.

Task reminders use the web reminderMinutes field (1–10080 minutes). Reconcile a bounded horizon of pending local notifications when planner, preferences, account, or app foreground state changes. Use profile timezone, exact wall-clock times, and the earlier repeated time across DST; skip nonexistent times. Remove cancelled/completed/archived/account-old requests. Do not remove unrelated bedtime notifications. Notification permission is requested only from a user action.

Verify restoration/unknown schemas, stale/account/plan/timezone mismatches, atomic mixed batches, retry after commit, receipt pruning, reminder schema and DST, recurring logical identity and event exceptions; run all core tests and unsigned app/widget build before routine auto-merge. Automatic multi-assignment planning and timeline drag/Undo remain later work.
