# 019 · The helper tabs come back after a herdr restart; tests leave nothing running
Status: Approved (the owner, 18 Nov 2026: "ok")
Size: S (≤ 2 h)

## Goal
After a herdr restart, `squad up` brings back the whole team, not only the agents: the strip that feeds the
sidebar, the observer's watcher, the report and lazygit. On 17 Nov 2026 these stayed empty shells until the
lead restarted them by hand. A queued dispatch whose team is gone stops at once, so tests and deleted teams
leave no process behind.

## Scope
- In: `squad up` (resume) restarts the `watch`, `observe`, `report` and `changes` panes when their pane runs
  only a shell; a queued dispatch exits when its `.team` folder is gone.
- Out: the agents' own restart (it works), new tabs, any change to the layout.

## Done when
- [ ] Resume with the four helper panes present but idle (only a shell): each pane runs its command again
      (`squad watch`, `squad watch --observe`, `squad report --live`, `lazygit`); a helper pane that runs its
      command is left alone.
- [ ] A queued dispatch whose `.team` folder is deleted exits within one poll.
- [ ] After `bash test/smoke.sh`, no `squad dispatch` process from the test is still running.
- [ ] Smoke passes on `/bin/bash` 3.2 and in CI; shellcheck is clean.

## Plan
- bin/squad: `revive_helpers <workspace>` in the resume path: for each helper label, `herdr pane process-info`;
  only a shell → `herdr pane run` its command.
- bin/squad `dispatch_queue`: `[ -d "$TEAM_DIR" ] || exit 0` at the top of each poll.
- test/smoke.sh: a resume case with the stand-in's process info; a deleted-team case; a check at the end of
  the suite for leftover processes.

## Tests
- Smoke: the stand-in reports a shell for the helper panes; the log shows the four `pane run` calls; a pane
  that runs `squad watch` gets none.
- Smoke: a queued dispatch, then `rm -rf .team`: the waiter is gone after one poll.

## Assumptions & open questions
- Assumption: "only a shell" means the pane's foreground process is the login shell (`-zsh`, `bash`, `sh`).
