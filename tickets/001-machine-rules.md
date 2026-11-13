# 001 · Machine rules in the script: lock, dispatch, ledger, Stop hook switch
Status: Approved (V!, 13 Nov 2026)
Size: M

## Goal
Rules that the hive team had to improvise in SPEC (the lock, the dispatch, the dispatch
log) move into `bin/squad`, so they always work the same way and cannot be skipped.

## Scope
- In: `squad heavy`, `squad dispatch`, ledger lines in `events.log`, the Stop hook switch
  in team worktrees, the matching role and protocol text.
- Out: the observer (003), QA changes (002), any change to V!'s global hook files.

## Done when
- [x] `squad heavy -- <cmd>` runs one heavy command at a time per team: first come, first
      served; the lock `.team/heavy/lock` is a link whose target names the seat, the pid and the time (one atomic step), and `.team/heavy/lock.cmd` names the command; a run over the
      time limit (`heavy_timeout` in team.conf, default 20 min) is stopped and released;
      a lock whose owner process is gone is released by the next caller.
- [x] `squad dispatch <seat> <ID>` sends the clear command, waits until the seat is idle,
      sends the task line, and fails with a message when the seat did not start within 60 s.
- [x] `events.log` gets one line for each dispatch, done, review verdict, merge and
      decision (`YYYY-MM-DD HH:MM:SS <seat> <ID> <EVENT> [detail]`: the date, because a run spans midnight); `squad merge <ID>` merges and logs.
- [x] `squad up` creates `.agents-verify-off` in every team worktree and adds it to
      `.git/info/exclude`, when `verify_hook off` is in team.conf (default: on — see open
      question 1).
- [x] Role files and PROTOCOL use these commands; no `sleep 3` and no `mkdir` lock text left.
- [x] `bash test/smoke.sh` and `shellcheck` pass (also under bash 3.2 in CI).

## Plan
- `bin/squad`: `cmd_heavy` (queue dir with one file per waiter, sorted by time; `owner`
  file; `kill -0` check on the owner pid; timeout with `timeout`-like loop in bash 3.2).
- `cmd_dispatch` using `herdr agent list` states and `herdr agent prompt`; `log_event` helper
  used by done, dispatch, merge.
- `setup_worktree`: the verify switch.
- `templates/roles/*.md`, `templates/PROTOCOL.md`: replace the manual steps.

## Tests
- smoke: two `squad heavy` calls in parallel run in order; owner file content; dead owner
  released; timeout releases.
- smoke: `squad dispatch` against the herdr stand-in (idle → prompt sent; never idle → fail).
- smoke: events.log lines for dispatch, done, merge.
- smoke: `.agents-verify-off` present and excluded with `verify_hook off`; absent without.

## Assumptions & open questions
1. **Open decision for V!:** turn off your global Stop/verify hook inside team worktrees?
   Recommended: yes, as an opt-in line `verify_hook off` that `squad init` writes. Reason:
   OBSERVER #7 — hidden whole-repo runs outside the lock, cancelled at 300 s. The tester's
   full run stays the gate.
2. Assumption: herdr's `agent list` status `idle` is a safe signal that `/clear` finished.

## Evidence (13 Nov 2026)
`bash test/smoke.sh`: 234 passed under bash 5 and under /bin/bash 3.2.57; `shellcheck -S warning`: clean. smoke: 'heavy runs one command at a time, in arrival order', 'the lock names its owner while it runs', 'a lock whose owner process is gone is cleared', 'a run over the time limit is stopped (exit 124)', 'a stopped heavy run leaves no command behind', 'dispatch gives dev-a its task once it is idle again', 'dispatch fails when the seat never starts, and logs it', 'merge merges an approved task', 'event lines carry the date and the time', 'decisions --check writes each decision into the ledger once', 'verify_hook off marks every team worktree', 'the lead dispatches through squad dispatch'. Not verified on real herdr: that `idle` follows `/clear` (assumption 2).
