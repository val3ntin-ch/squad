# 007 · Heavy runs on committed code, and a shorter limit for dev runs
Status: Approved (V!, 13 Nov 2026)
Size: S

## Goal
A heavy run tests only committed code, so a killed run never leaves an edit behind and the
result names the commit it proves. A dev's diagnostic run holds the shared lock for less time
than the tester's full run. Source: hive observer passes 57–62 (decision 54 broken three times
in an hour; `sed -i` edits inside lock scripts; dev runs of 21–25 min while two devs waited).

## Scope
- In: `squad heavy` refuses a dev seat whose worktree has uncommitted changes; the commit is
  recorded in the lock and in `HEAVY_START`; `heavy_timeout_dev` in team.conf; role and
  protocol text; README.
- Out: per-seat sandboxes or machines (isolation instead of a lock): an open decision for V!,
  pending the research; the tester's and the lead's runs (no commit rule for them).

## Done when
- [x] `squad heavy <dev seat> …` exits 1 with "commit first" and the changed files when the
      seat's worktree has staged, unstaged or untracked changes; with a clean worktree it runs.
- [x] `HEAVY_START` in events.log and `squad heavy --status` name the commit (short sha).
- [x] A dev seat's run stops after `heavy_timeout_dev` minutes (shipped presets: 10); the tester
      and the others keep `heavy_timeout` (20). `HEAVY_START` names the limit.
- [x] The dev role and PROTOCOL say: commit (a WIP commit is fine), then `squad heavy`; a
      diagnostic variant is a commit or a separate test file, never an edit inside the run.
- [x] `bash test/smoke.sh` and `shellcheck` pass, under bash 5 and 3.2.

## Plan
- `bin/squad`: `HEAVY_TIMEOUT_DEV` in load_conf; in `cmd_heavy`, for a dev seat, check
  `git -C <seat worktree> status --porcelain` before queueing; the limit by role; the sha in
  `lock.cmd` and in the event.
- `templates/PROTOCOL.md`, `templates/roles/dev.md`, presets, README.

## Tests
- smoke: dirty dev worktree refused (modified file, and untracked file); clean runs; a dirty
  tester worktree runs; the event names the sha and `limit=10m` for a dev, `limit=20m` for the
  tester.

## Assumptions & open questions
1. The rule applies to dev seats only (decision 54 is about devs; the tester checks out
   detached commits and writes its artefacts under `.team/`).
2. Open decision for V! (after the research): isolation per seat instead of one shared lock.

## Evidence (13 Nov 2026)
`bash test/smoke.sh`: 245 passed under bash 5 and /bin/bash 3.2.57; `shellcheck -S warning`: clean.
Smoke: 'heavy refuses a dev worktree with an untracked file', '… with a staged change', 'a refused
run takes no lock and leaves no queue entry', 'heavy runs a clean dev worktree', 'the run names the
commit and the dev limit', 'the tester's run is not held to the commit rule', 'the tester keeps the
longer limit', 'the dev role says commit before squad heavy'. Market check:
docs/research/2026-11-13-software-factories.md (rows 1, 2, 6, 7).
