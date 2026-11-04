# Planner loading and task creation layout

Evidence: iOS requires scheduleEvents.day, while web NativeEventWrite supports dated events with no day. The screenshot's generic decoding message does not identify the actual account field; expose precise DecodingError paths so other incompatible fields can be diagnosed without inspecting personal values. Keep task identity and known field types strict.

Allow an optional day and optional explicit date on schedule events, default missing category to other, and adapt both event displays/exports. An explicit date takes precedence over a legacy weekday. Preserve raw web metadata when other planner edits are saved. Show a failed-load panel with Retry instead of a misleading empty checklist.

Reserve a separate VStack slot for the bottom navigation bar. Keep the creation dock inside the reduced content viewport, so nested NavigationStacks cannot cover it with the outer tab bar.

Regression coverage: dated and weekly event decoding, Sunday zero, explicit-date export precedence, invalid date rejection, precise nested decode paths and preservation of web event metadata during edits. Verify full Swift tests and simulator build on macOS CI. Actual account loading and layout on device still require user validation.