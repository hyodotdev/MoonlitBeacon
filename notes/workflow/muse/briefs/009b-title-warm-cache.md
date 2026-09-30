# Brief 009b: Completed loads are valid on a warm cache

Continue the same title-test run. The director found one new deterministic false failure in its new
`first_status == THREAD_LOAD_IN_PROGRESS` assertion. The original eleven assertions did not require
catching a transient intermediate state.

A temporary external SceneTree diagnostic runtime-loads and holds the actual arena PackedScene, then
instantiates the actual title-transition test scene. No production or test files were modified. It fails
only `worker load observed in flight`: expected 1, actual 3; the other 21 cases pass and the worker request
returns the correct arena. Evidence is the run's `judge-director-title-warm-runtime.log`. The earlier
external-preload attempt failed because it compiled before autoloads; that attempt is not the finding.

Accept both a genuine in-progress observation and an already-completed load at the first poll. Keep the
real request assertion, final LOADED assertion, full progress, deadline, PackedScene/path checks, freed
title guard and all original checks. Register a deterministic warm-cache case that holds the runtime-
loaded arena, kicks the real title request and drains it; do not require catching IN_PROGRESS there.
The normal and slower/concurrent diagnostics still exercise the bounded wait. No production changes,
filtering or scope expansion. Retest normal and warm-cache paths plus the deadline negative; finish the
report with the remaining pre-existing RefCounted warning scope.
