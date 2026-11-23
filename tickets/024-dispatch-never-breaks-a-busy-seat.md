# 024 · A dispatch never interrupts a busy seat, and a dev is never idle for long
Status: Done — awaiting PR review
Size: M (≤ 1 day)

## Goal
Squad's own commands stop causing lost work. Seen in hive on 20 and 21 Nov:
- A queued dispatch cleared a seat that was waiting on its own test run or in the lock
  queue (dev-b 20:35, tester 22:03; the lead took such tasks back, 5 `WITHDRAWN` events;
  hive LESSONS L-12 and L-15). The seat read as "idle".
- The lead reported that `squad plan --help` created a draft plan that blocked every new
  dispatch (21:55).
- dev-b had no task from about 02:00 to 06:45 (6 `IDLE` events). Squad told the lead each
  time and nothing more happened.

## Scope
- In: `squad dispatch` and its queue, `squad plan` argument handling, the idle alarm in
  `squad watch`, the smoke tests.
- Out: hive's rules; the stuck-seat alarms of ticket 023; review and test rules.

## Done when
- [ ] A seat that has a heavy run alive or waits in the lock queue is "busy": a dispatch to
      it stays queued until the run ends; nothing is cleared.
- [ ] The same seat (live heavy run, or a place in the lock queue) gets no STALLED and no
      IDLE alarm.
- [ ] `squad plan --help` (and `-h` on every command) prints help and changes no file.
- [ ] A dev with no task for 30 min while open tasks exist sends val3ntin-ch one herdr notification
      (seat, minutes idle, the number of open tasks), after the lead was told at 5 min.
- [ ] `test/smoke.sh` passes, with a test for each item above that fails before the change.

## Plan
- Reuse the "busy" test of `seat_trouble` (fresh heartbeat or lock owner) plus the lock
  queue in the dispatch queue's readiness check.
- A `Stop` hook writes the seat's state: its input has `background_tasks` (tested on
  Claude Code 2.1.323), so "free" and "waits for its own run" are told apart without
  reading the screen.
- Find where `plan` parses its first argument; handle `--help` before any write. First
  reproduce the lead's report; if it does not reproduce, write what happened instead.
- `idle_dev_check`: a second step at 30 min with `v_notify`.

## Tests
One smoke test per "Done when" item.

## Assumptions & open questions
- The `plan --help` defect is from the lead's log, not yet reproduced.

## Verification
Independent verifier, 22 Nov 2026, on the pushed code; four real trials on a throwaway team (real herdr 0.9.5, real Claude Code 2.1.323 seats).

| Item | Result | Evidence |
|---|---|---|
| A busy seat's dispatch stays queued, nothing cleared | PASS | smoke "024: a dispatch to a seat that waits in the heavy lock queue…"; real trial 1 (check F) |
| No STALLED and no IDLE alarm for it | PASS | smoke "024: … is not stalled", "… gets no IDLE alarm" |
| `-h` and `--help` print help, change no file | PASS | smoke "024: -h and --help print the help on every command"; real trial 1 (check A) |
| A dev idle 30 min with open tasks: one notification to val3ntin-ch | PASS | smoke "024: at 30 min the owner gets one notification…", "trial 26: …" |
| `test/smoke.sh` passes | PASS | 851 passed, 0 failed; CI green |
