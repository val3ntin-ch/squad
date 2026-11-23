# 034 · A free dev gets its next task without waiting for an alarm
Status: Approved (V!, 23 Nov 2026: "ok all, proceed"); the measurement comes first
Size: M (≤ 1 day)

## Goal
A dev that reports DONE starts its next task at once, also while V! sleeps. Today the lead
gives the next task after the 5-minute idle alarm, and V! gets a notification after 30 min.

Measured on hive, 22 Nov 19:26 to 22:31: 8 idle alarms, 4 of them "no task for 30 min, 124
open task(s): V! is told". Assumed, not measured: that those open tasks were ready for a dev;
many may wait for V!'s answers.

## Scope
- In: a ready list per dev that the lead fills; the delivery of its first task at the dev's
  DONE; the idle notification to V!.
- Out (not in this ticket): which task a dev gets (the lead decides the list); tickets 032
  and 033.

## Done when
- [ ] Measurement first: for each idle alarm since 22 Nov 02:34, how many open tasks had a
      brief and no open question for V!. If the number is 0 for most alarms, this ticket
      closes with that result and no code.
- [ ] `squad ready <dev> <task>…` records the dev's next tasks; at the dev's DONE squad
      dispatches the first one and logs `DISPATCH` with `from=ready`.
- [ ] The 30-minute idle notification goes to V! only when the dev's ready list is empty and
      a task without an open question exists.
- [ ] `test/smoke.sh` passes in CI, with a test for each code item that fails before the
      change.

## Plan
- The measurement, from `events.log` and `TASKS.md` history; report it to V!.
- The ready list as files beside the dispatch queue; delivery through the same queue code.

## Tests
One smoke test per code item; the measurement is a script with its output in the ticket.

## Assumptions & open questions
- Open decision for V!: this changes the rule of 18 Nov that only the lead starts a
  dispatch: here squad starts one that the lead queued. Options: (a) keep the rule and set
  `idle_minutes 2`; (b) the ready list. Recommendation: (b), after the measurement.
