# 030 · A notice always reaches the lead; DONE needs the cheap checks; a seat can run without MCP servers
Status: Done — awaiting PR review (approved by val3ntin-ch on 22 Nov 2026: "fix it, also be sure that if needed we fix all now"; the three changes of scope below: val3ntin-ch, 22 Nov 2026, "yes to pr 28")
Size: M (≤ 1 day)

## Goal
Remove the three largest losses measured on hive after tickets 023 to 027 were installed
(report "Squad factory next improvements", 22 Nov 2026):
- The reviewer's notice did not reach the lead 21 times of 21 (280 min): the Codex seat
  ran its report write and `squad done` as one shell command, so the command ran in
  Codex's sandbox, where herdr cannot be reached.
- All 6 failed candidates and 7 of 17 review findings were a check the dev did not run
  before DONE (unit tests of a package, `knip`).
- The machine ran about 1,500 processes: each seat starts every MCP server of the user's
  configuration.

## Scope
- In: `squad done` (the send of the notice, the DONE gate), `squad watch` (delivery of a
  notice that was not sent), two settings in `load_conf` (`done_check`, `seat_mcp`), the
  start options of a Claude seat, `templates/roles/dev.md`, `templates/roles/reviewer.md`,
  `templates/roles/tester.md` (the same "own command" sentence), `templates/PROTOCOL.md`,
  the smoke tests, README.
- In (added in the build; val3ntin-ch, 22 Nov 2026): the short lock `mutex()` takes its claim in one
  step (a file made by bash with `set -C`, not `mkdir`, which is not a one-step claim on
  the Rust coreutils 0.2.2 to 0.10.0), and every place that releases such a lock removes
  the file. This includes the one line that releases the lock in `squad merge` and in
  `squad candidate`.
- Out: who judges a reviewer's finding; the logic of `squad merge` and the candidate check; which
  checks a candidate runs; Codex's own rule list.

## Done when
- [x] When `squad done` cannot reach herdr (the send fails for a reason other than a
      dialog in the lead's pane), the event is logged, the notice is kept as not sent, the
      command says so and exits 0, and `squad watch` sends the notice to the lead at its
      next tick, once.
- [x] With `done_check <text>` lines in `team.conf`, `squad done <dev> <task> DONE` is
      refused unless, for each line, that dev has a `squad heavy` run for that task on the
      task's current commit whose command is the text, whole (as written, or as a step of a
      `--batch` run; a `--sample` run and a narrowed run do not count), and which ended
      with exit 0; the refusal names each missing check and the commit. With no
      `done_check` line nothing changes. (val3ntin-ch, 22 Nov 2026: the first text said "contains
      the text"; review showed that a partial run then passes.)
- [x] With `seat_mcp none` a Claude seat starts with no MCP server (verified on the real
      Claude Code CLI); `seat_mcp inherit` (the default) starts it as today; the setting
      can name seats (`seat_mcp none tester observer`).
- [x] The role files say: run `squad done` as its own command, never joined to another
      command; a dev runs the team's `done_check` commands on its last commit before DONE.
- [x] `test/smoke.sh` passes in CI (Ubuntu, macOS with bash 5 and bash 3.2), with a test
      for each item above that fails before the change.

## Plan
- `cmd_done`: on a failed `herdr agent prompt`, the same "not sent" marker the dialog case
  writes; `notices_tick` already delivers it.
- The DONE gate beside `done_gate`: read the seat's `HEAVY_START` (commit, command) and
  `HEAVY_END` (exit code) events of the task.
- `seat_mcp`: find the documented Claude Code start options that load no MCP server
  (`--strict-mcp-config` with an empty `--mcp-config`); test them on the installed CLI
  with `claude -p` before use.
- The full suite runs in GitHub CI, not on the team's machine (it slowed the live team).

## Tests
One smoke test per "Done when" item; the `seat_mcp` item also by one real `claude -p` call.

## Assumptions & open questions
- Open decision for val3ntin-ch: which hive seats get `seat_mcp none` (the devs may use the
  Playwright MCP server for screenshots), and hive's `done_check` lines (proposed: the
  unit tests of `@hive/ui`, of `@hive/storybook`'s non-browser tests, and `knip`).
- Known limits (review of commit 11a4161, 22 Nov 2026):
  - (a) When `herdr agent prompt` exits non-zero after it already typed the line, the lead
    gets the notice a second time at the next tick. A duplicate is accepted; a lost notice
    is not.
  - (b) A failed run after a passed run on the same commit and command does not take the
    pass back.
  - (c) A run that outlived its budget and whose lock was cleared can make a later real
    pass be refused (the safe direction). A run id in the events would fix it.
  - (d) Pre-existing in `mutex()`, not changed here: the stale rule (older than 1 minute,
    check then remove) can remove a fresh or a long-held lock. It needs an owner in the
    lock; that is a later ticket.
  - (e) An older squad on the same machine cannot clear a stale lock file of a crashed new
    squad. Install the new binary before you add `done_check` or `seat_mcp` lines to
    `team.conf`: an old binary stops on the unknown keyword.

## Verification
Independent verifier, 22 Nov 2026, on the pushed code (b405fd1); a real trial on a throwaway team (real herdr, real Claude Code 2.1.323 seats; `squad-trial/evidence7`).

| Item | Result | Evidence |
|---|---|---|
| A `squad done` that cannot reach herdr: event logged, notice kept, exit 0, the watch sends it once | PASS | smoke "030: squad done with no herdr in reach…", "…squad watch sends that notice… once"; by hand in a throwaway team; real trial check B (a sandboxed `cat … && squad done`) |
| `done_check`: DONE refused without a passed whole run on the task's commit; no line, no change | PASS | 19 smoke checks "030: …" (failed run, other task, other seat, new commit, narrowed run, `--sample`, the `bash -c` form); real trial check C |
| `seat_mcp none`: a Claude seat starts with no MCP server; `inherit` as before; named seats | PASS | real CLI call: 0 MCP servers, 0 MCP tools; 8 smoke checks; real trial check A (`/mcp`: "No MCP servers configured") |
| Role files: `squad done` as its own command; the dev runs the `done_check` commands | PASS | diff of `dev.md`, `reviewer.md`, `tester.md`, `PROTOCOL.md`; 2 smoke checks |
| `test/smoke.sh` passes in CI, with a test for each item that fails before the change | PASS | CI run 45023015654 on b405fd1: Ubuntu and macOS (bash 5 and bash 3.2) green; the 47 "030:" checks against 94270ab: 36 fail |
| The short lock claims in one step (added scope) | PASS | smoke "030: three callers of one mutex at once…" with a stand-in `mkdir`; real trial check D |
| The three changes against the first ticket text (whole-command match, the lock, `tester.md` and the lock release in merge and candidate) | PASS | val3ntin-ch, 22 Nov 2026: "yes to pr 28" |

