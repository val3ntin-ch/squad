# 034 · A free dev gets its next task without waiting for an alarm
Status: Measured 23 Nov 2026: the ready list is not needed (no code); a new defect waits for val3ntin-ch
Size: M (≤ 1 day)

## Goal
A dev that reports DONE starts its next task at once, also while val3ntin-ch sleeps. Today the lead
gives the next task after the 5-minute idle alarm, and val3ntin-ch gets a notification after 30 min.

Measured on hive, 22 Nov 19:26 to 22:31: 7 idle alarms, 3 of them "no task for 30 min, 124
open task(s): <owner> is told". Assumed, not measured: that those open tasks were ready for a dev;
many may wait for val3ntin-ch's answers.

## Scope
- In: a ready list per dev that the lead fills; the delivery of its first task at the dev's
  DONE; the idle notification to val3ntin-ch.
- Out (not in this ticket): which task a dev gets (the lead decides the list); tickets 032
  and 033.

## Done when
- [ ] Measurement first: for each idle alarm since 22 Nov 02:34, how many open tasks had a
      brief and no open question for val3ntin-ch. If the number is 0 for most alarms, this ticket
      closes with that result and no code.
- [ ] `squad ready <dev> <task>…` records the dev's next tasks; at the dev's DONE squad
      dispatches the first one and logs `DISPATCH` with `from=ready`.
- [ ] The 30-minute idle notification goes to val3ntin-ch only when the dev's ready list is empty and
      a task without an open question exists.
- [ ] `test/smoke.sh` passes in CI, with a test for each code item that fails before the
      change.

## Plan
- The measurement, from `events.log` and `TASKS.md` history; report it to val3ntin-ch.
- The ready list as files beside the dispatch queue; delivery through the same queue code.

## Tests
One smoke test per code item; the measurement is a script with its output in the ticket.

## Assumptions & open questions
- Open decision for val3ntin-ch: this changes the rule of 18 Nov that only the lead starts a
  dispatch: here squad starts one that the lead queued. Options: (a) keep the rule and set
  `idle_minutes 2`; (b) the ready list. Recommendation: (b), after the measurement.

## Measurement (23 Nov 2026, hive's TASKS.md as of 22 Nov 22:31 and events.log)
- The idle alarm to val3ntin-ch counts every row of TASKS.md whose status cell is not exactly
  `merged`. Hive writes `**merged** 21 Nov 23:15 (candidate 74 …)` or `merged (CANDIDATE-117)`,
  so 104 merged tasks count as open: squad's count is 125, the real number of rows that are
  not merged in any form is 21.
- None of the 21 was ready for a dev without val3ntin-ch or a new brief:
  - 4 wait for val3ntin-ch: T-136, T-141, T-158 (decision D-100), T-148.
  - 6 are done, closed or not needed: T-128, T-170, T-172, T-174, T-176, T-179.
  - 6 are parent tasks whose sub-tasks are merged or in a candidate: T-157, T-159, T-160,
    T-161, T-162, T-164.
  - 1 is approved and in a candidate: T-160i.
  - 2 are placeholders: T-2xx, T-3xx.
  - 1 needs its brief: T-167. 1 is a harness in progress: T-150.
- Commands (read 23 Nov 2026 on `/Users/v/v-dev/hive/.team/TASKS.md`, changed 22 Nov 22:31):
  - squad's old count: `awk -F'|' '/^\| *T-[0-9]/ { st = $5; gsub(/^ +| +$/, "", st); if (st != "merged") n++ } END { print n }'` → 125
  - rows not merged in any form: `awk -F'|' '/^\| *T-[0-9]/ { if (tolower($5) !~ /merged/) n++ } END { print n }'` → 21
- Known limit: TASKS.md has no history (it is not in git), so this is one reading of the table
  at the end of the night, not one reading per alarm. The 9 alarms to the owner in the log
  (13 to 22 Nov) reported 116 to 125 open tasks, the same size as the miscount on this
  reading.
- Result: the free devs had no ready task; a ready list per dev would have held nothing. The
  "Done when" rule of this ticket applies: no code for the ready list.

## New defect found (not built: open decision for val3ntin-ch)
The alarm "no task for 30 min, 124 open task(s): val3ntin-ch is told" is wrong twice: the number is
wrong, and the real reason (the work waits for val3ntin-ch's decisions) is not named.
- Option (a): count a row as open only when its status does not contain `merged`, `done`,
  `closed` or `not needed`.
- Option (b): as (a), and the notification names the rows that wait for val3ntin-ch ("waits for val3ntin-ch",
  "D-<n>" in the status), so val3ntin-ch sees what unblocks the team.
- Recommendation: (b), as a small ticket 035.
