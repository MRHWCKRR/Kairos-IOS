# Task-linked native focus

Build: a shared recoverable native timer for general focus, ordinary tasks and dated recurring occurrences; exact retry logging through the web receipt/history format; lifetime current-planner focus by board, assignment and task with estimate comparison.

Use the existing timer/Live Activity shell and shared web focus/occurrence/history/breakdown models. Persist an account-scoped checkpoint and immutable pending log atomically before saving. Running sessions retain the existing native background timing while the process survives. Checkpoint on scene changes and recover paused at the last checkpoint after relaunch, without guessing time after a crash. Keep pending requests across errors and account changes; never replace active work or silently reset a failed log.

Transactions read the user and captured owned planner before any writes, check the active planner/account, reuse receipt IDs, and merge only changed raw focus leaves. Ordinary and recurring ledgers stay separate. Logging does not change completion, estimates, checklists or schedules. Missing/moved/reassigned targets use the shared log-only fallback to overall totals with feedback. Corrections/manual entries and remaining-work check-ins are later features.

Checks: real-model Node tests for attribution, recurrence identity, duplicates, retries, receipt expiry, midnight/timezones and breakdown totals; Swift tests for raw metadata preservation, strict shape checks and local recovery/pending invariants; macOS suite in three timezones, native app/widget and existing layout/icon checks. Device interaction remains a manual check.
