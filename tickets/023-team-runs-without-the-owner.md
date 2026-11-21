# 023 · The team keeps running without the owner watching
Status: Approved (V!, 21 Nov 2026: "make all the fixes and improvements asap")
Size: M (≤ 1 day)

## Goal
Squad finds a stuck seat and either fixes it or tells V! within minutes. Today a seat can
stop for hours and nobody acts. Seen in hive:
- dev-c waited 9 h (20 Nov 23:42 to 21 Nov 08:47) on a question only V! can answer.
  Squad told only the lead, which cannot answer it.
- After the herdr restart of 17 Nov, seats ran for about 2.5 days without their squad
  options; the observer's passes were refused (no permission mode) until it was
  restarted on 20 Nov.
- The stall alarm fires only when no seat works, so one stuck seat among working ones
  is never reported.

## Scope
- In: `squad watch` (the watchdog), `bin/squad` helpers it calls, the smoke tests, README.
- Out: hive's own rules and tasks; herdr itself; any change to how reviews or tests run.

## Done when
- [ ] A seat in herdr state `blocked` for 5 min gets a herdr notification to V! that names
      the seat, its task and the first line of its question; one notification per wait.
- [ ] A seat that runs without its squad options (no `--append-system-prompt-file`
      `.team/seats/<seat>.md` in its process) or is gone is restarted with its full
      options by `squad watch` with `seat_restart on` (default `off`: squad only tells V!), at most once per 10 min per seat, with an event line (after 3 restarts of a seat in
      one hour squad stops and notifies V!);
      a lead or dev with an open task gets its task re-sent after the restart.
- [ ] One stuck seat (blocked, stalled or dead) is reported while other seats work.
- [ ] A long-running `squad watch` picks up a new `bin/squad` without a manual restart.
- [ ] `test/smoke.sh` passes, with new tests for each item above.

## Plan
- `watchdog_tick`: add a per-seat pass: `blocked` for ≥ 5 min → `v_notify` with the
  question text (from `agent read --source visible`), keyed per seat and wait.
- Seat options check: read the seat's process args (`herdr pane process-info`); missing
  squad options or `off` with an open task → the same resume path `squad up` uses.
- Remove the "no seat working" condition for the per-seat alarms; keep it for the
  team-wide stall alarm only.
- `cmd_watch`: when `bin/squad` changes on disk, `exec` itself again.
- Use Claude Code hooks as the first signal, the screen as the second (tested on Claude
  Code 2.1.323, 21 Nov): a `PermissionRequest` hook (it fires at once, with the tool and
  its input) and a `PreToolUse` hook on `AskUserQuestion` write "waits for the owner since
  T" to the seat's state file and call `v_notify`; a `StopFailure` hook reports a usage
  limit or a sign-in error at once.
- Write the seat hooks to the worktree's `.claude/settings.local.json` too, not only to
  the `--settings` file, so a seat that herdr resumed without options still has them; its
  `SessionStart` hook (source `resume`) then reports "runs without squad options".
- Tests with the fake herdr of `test/smoke.sh`.

## Tests
One smoke test per "Done when" item, each failing before the change.

## Assumptions & open questions
- V!'s notification is herdr's toast (already enabled, 17 Nov).
- Squad never answers a seat's question or permission prompt itself; it only tells V!.
- V!, 21 Nov 2026: the automatic restart ships switched off (`seat_restart off`); squad tells V! and types nothing.
