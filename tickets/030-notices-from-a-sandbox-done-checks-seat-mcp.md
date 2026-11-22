# 030 · A notice always reaches the lead; DONE needs the cheap checks; a seat can run without MCP servers
Status: Approved (V!, 22 Nov 2026: "fix it, also be sure that if needed we fix all now")
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
  `templates/PROTOCOL.md`, the smoke tests, README.
- Out: who judges a reviewer's finding; `squad merge` and the candidate check; which
  checks a candidate runs; Codex's own rule list.

## Done when
- [ ] When `squad done` cannot reach herdr (the send fails for a reason other than a
      dialog in the lead's pane), the event is logged, the notice is kept as not sent, the
      command says so and exits 0, and `squad watch` sends the notice to the lead at its
      next tick, once.
- [ ] With `done_check <text>` lines in `team.conf`, `squad done <dev> <task> DONE` is
      refused unless, for each line, that dev has a `squad heavy` run for that task on the
      task's current commit whose command contains the text and which ended with exit 0;
      the refusal names each missing check and the commit. With no `done_check` line
      nothing changes.
- [ ] With `seat_mcp none` a Claude seat starts with no MCP server (verified on the real
      Claude Code CLI); `seat_mcp inherit` (the default) starts it as today; the setting
      can name seats (`seat_mcp none tester observer`).
- [ ] The role files say: run `squad done` as its own command, never joined to another
      command; a dev runs the team's `done_check` commands on its last commit before DONE.
- [ ] `test/smoke.sh` passes in CI (Ubuntu, macOS with bash 5 and bash 3.2), with a test
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
- Open decision for V!: which hive seats get `seat_mcp none` (the devs may use the
  Playwright MCP server for screenshots), and hive's `done_check` lines (proposed: the
  unit tests of `@hive/ui`, of `@hive/storybook`'s non-browser tests, and `knip`).
