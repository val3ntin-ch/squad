# 025 · A verdict reaches the lead, and a wait for the owner is a known state
Status: Done — awaiting PR review
Size: M (≤ 1 day)

## Goal
A report or a verdict for the lead is never lost in one unread line, and squad can tell a
chosen wait for the owner from a lost one. In hive, verdicts waited 52.8 h in sum for the
lead (one for 15.4 h), and waits of 36 h and 64 h for the owner produced no notification
(report "Software factory improvements for squad", ranks 2 and 6 of the decisions table).

## Scope
- In: `squad done` and the reviewer and tester verdict notices to the lead, `squad watch`
  (the watchdog), a new `squad wait-owner` command, `v_notify`, the smoke tests, README,
  `templates/roles/lead.md`.
- Out: dispatches (squad still never re-sends a dispatch by itself: val3ntin-ch, 18 Nov); who judges
  a reviewer's finding (the lead, as today); a phone channel.

## Done when
- [ ] Each notice to the lead (DONE, a reviewer or tester verdict, BLOCKED) is kept as a
      pending record until an event of the lead for that task appears in `events.log`;
      while it is pending, `squad watch` sends the notice line again to the lead every
      `notice_redeliver_minutes` (default 15) and notifies val3ntin-ch once after
      `notice_owner_minutes` (default 30).
- [ ] `squad wait-owner "<what>"` (the lead runs it) writes the wait, notifies val3ntin-ch once, and
      reminds val3ntin-ch every `owner_reminder_hours` (default 4) until `squad wait-owner --done`
      or a new dispatch; while it is set, the team-wide stall alarm is silent.
- [ ] A notification to val3ntin-ch for a condition that still holds is repeated every 30 min, at
      most 3 times, and stops when the condition ends.
- [ ] With `notify_os on` (the default) `v_notify` also sends an operating-system
      notification on macOS; `notify_os off` keeps herdr's toast only.
- [ ] `test/smoke.sh` passes, with a test for each item above that fails before the change.

## Plan
- Pending notices: one small file per notice under `.team/observer/.notices/`, written by
  the code that sends the line today, removed by the watch loop when the lead's event for
  the task is newer.
- `watchdog_tick`: a pass over the pending notices and over the owner wait file.
- `v_notify`: the repeat counter per key; `osascript` for the OS notification, skipped
  when the command is missing.
- `lead.md`: when to run `squad wait-owner`.

## Tests
One smoke test per "Done when" item.

## Assumptions & open questions
- Report decisions 1, 2, 4, 5 and 6: the recommended options are built, as settings of
  `team.conf` where they change behaviour. val3ntin-ch can change each one.
- Technical choices, to be confirmed by val3ntin-ch: after val3ntin-ch was told, a notice is re-sent to the lead 3 more times and then stops; the lead ends a notice with the new command `squad seen <task>` (a reviewer found that a notice could be re-sent for ever when the lead answered in another way).

## Verification
Independent verifier, 22 Nov 2026, on the pushed code; four real trials on a throwaway team (real herdr 0.9.5, real Claude Code 2.1.323 seats).

| Item | Result | Evidence |
|---|---|---|
| A notice is kept, re-sent every `notice_redeliver_minutes`, val3ntin-ch told after `notice_owner_minutes` | PASS | smoke "025: a notice to the lead is kept…"; real trials 1, 2 and 4 |
| `squad wait-owner` | PASS | smoke "025: squad wait-owner writes the wait…"; real trial 1 (check H) |
| A notification repeats every 30 min, 3 times at most | PASS | smoke "025: … repeated 3 times at most" |
| `notify_os` | PASS | smoke "025: with notify_os on…"; real trial 1 (osascript called once) |
| `test/smoke.sh` passes | PASS | 851 passed, 0 failed; CI green |
