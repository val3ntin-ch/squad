# 020 · Honest numbers: unknown cost, PASS with untested rows, queued tasks that survive
Status: Done — awaiting PR review (approved by the owner on 18 Nov 2026)
Size: M (≤ 1 day)

## Goal
The report and events.log never show a number or a result that was not measured. The audit check of 17 Nov 2026
proved three cases: a missing cost reading shows 0; a PASS with untested rows is logged as a plain PASS; a queued
task is lost at a restart, or dropped when an earlier send never started.

## Scope
- In:
  - Cost: a task whose quota reading is missing, or crosses a quota reset, shows `?`, not 0 (report and HTML).
  - PASS: when rows are pending, unavailable or inconclusive, events.log says so: `PASS … untested=2,3,4`.
  - Queue: the pending file keeps the dispatch arguments; `squad up` and the strip restart a queued dispatch
    whose waiter is gone; a `DISPATCH` followed by `DISPATCH_NOT_STARTED` or `DISPATCH_FAILED` does not count
    as sent.
- Out: per-task token measurement (a later ticket); refusing a PASS (that is ticket 018); any change to how
  quota is read.

## Done when
- [ ] A task with a missing or reset quota reading shows `?` in the report's TASKS and in the HTML Cost tab;
      a task with both readings still shows its number.
- [ ] `squad done tester X PASS` with pending rows logs `untested=` with those row numbers; with all rows
      passing it logs a plain PASS as today.
- [ ] A queued dispatch whose waiter was killed is sent again by the next `squad up` or strip tick, with the
      same arguments.
- [ ] A queued task is not dropped when the earlier `DISPATCH` ended in `DISPATCH_NOT_STARTED`.
- [ ] Smoke passes on `/bin/bash` 3.2 and in CI; shellcheck is clean.

## Plan
- bin/squad `task_stats_raw`: track a missing or reset reading per task; print `?`.
- bin/squad done gate: add `untested=` to the PASS event.
- bin/squad `dispatch_queue`: write the arguments into the pending file; `requeue_orphans` in `squad up` and
  the strip; `sent()` skips a DISPATCH that has a NOT_STARTED or FAILED after it.
- test/smoke.sh: one case per item.

## Tests
- Smoke cases for each "Done when" item (synthetic events; the herdr stand-in).

## Assumptions & open questions
- Assumption: two seats that work at the same time still share one quota window; the report keeps its note
  "an estimate, not exact tokens". Per-task tokens come with a later ticket.

## Verification
Independent verifier on 1f630ea: READY (457 passed, 0 failed on /bin/bash 3.2; shellcheck clean; no leftover process; SIGTERM keeps the queued request, checked with its own probe). Its one open point, a task never measured, now shows `?` (smoke "020: a task never measured shows ?, not 0"; 458 passed).
