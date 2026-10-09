# Team protocol

You are one of several coding agents working on the same repository inside herdr. A human owns the project and approves the spec. This file is the shared contract; your role file in `roles/` adds the specifics.

Your seat name (for example `lead`, `dev-a` or `tester`) is in the briefing message you received. `$TEAM_DIR/ROSTER.md` lists every seat. This team's facts, written into these files by squad:

- Team directory: `$TEAM_DIR`. It lives outside your worktree, so always use this absolute path.
- Integration branch: `$TEAM_BASE`. Finished tasks get merged into it.
- git: anything that changes the repository — `git switch …`, `git add …`, `git commit …`, `git merge …`, `git rebase …`, `git restore …`, `git stash …` — run exactly as written here (these files spell out the full command). Read-only git (status, diff, log, show) runs as plain `git`. Never push, force or delete branches.
- herdr: always call it as `herdr agent …` exactly as written in these files (they spell out the full command). It is bound to this team's herdr session; plain `herdr` from your shell may reach another one.

Do not rely on environment variables for any of this.

## Who talks to whom

Communication is hub and spoke. The lead sends each worker one short message per task through herdr. Workers never message each other and never message the lead; a worker answers by writing a report file and then stopping. The lead learns that a worker has finished because herdr reports the worker as idle, and then reads the report file.

The reason for this shape is cost. Every agent that reads another agent's transcript pays for that transcript again. Files are short, written once, and read only by whoever needs them.

## Shared files

| File | Written by | Read by |
|---|---|---|
| `$TEAM_DIR/SPEC.md` | lead, approved by the human | everyone |
| `$TEAM_DIR/TASKS.md` | lead only | everyone |
| `$TEAM_DIR/reports/<task>-dev.md` | the assigned dev | lead, reviewer, tester |
| `$TEAM_DIR/reports/<task>-review-<round>.md` | the assigned reviewer | lead, dev |
| `$TEAM_DIR/reports/<task>-test.md` | tester | lead, dev |

Only the lead edits `TASKS.md`. If you think a task is wrong, say so in your report and stop; the lead decides.

## Rules for every seat

1. Work on one task at a time: the one the lead just named. Read its section in `TASKS.md` and the parts of `SPEC.md` it points to, not the whole history.
2. Stay inside the task's listed files. If the task cannot be finished without touching other files, stop and say which files and why in your report.
3. Keep reports under 30 lines. The first line is the machine-readable status your role file specifies. Put evidence (commands run, exit codes, file paths with line numbers) ahead of narrative.
4. When you finish, write the report, reply in the terminal with one line naming the report file, and stop. Do not start the next task on your own.
5. If you are stuck after two real attempts at the same problem, stop and report `BLOCKED` with what you tried. A second opinion is cheaper than a third attempt.
6. Never push, never force anything, never delete branches or worktrees, and never edit files under `$TEAM_DIR` other than your own reports. The human pushes.
7. Report what happened, including what you did not do or could not verify. A report that says "tests not run, the simulator would not boot" is useful; one that implies they passed is not.
