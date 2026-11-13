# 010 · Seats never block on prompts, verified starts, true stalls, hung runs stopped
Status: Approved (V!, 14 Nov 2026; dev and tester seats unchanged)
Size: M

## Goal
Remove the five squad defects hive's observer measured after the v2 switch (passes 1–10, 13 Nov
22:08–23:24), each with the solution of the best agent factories, checked in their source code and
official docs (sources below).

## The issues and the solutions
| # | Issue (hive observer) | Cost | Solution and source |
|---|---|---|---|
| 1 | The Codex reviewer stopped 5 times on approval menus ("Allow the playwright MCP server…"); nobody may answer them | 10–14 min each; T-110 review stuck | Codex `-a never`: an MCP call that needs approval is refused, not asked (openai/codex `codex-rs/core/src/mcp_tool_call.rs:1854`); playwright off for the reviewer (`mcp_servers.<id>.enabled`, `codex-rs/config/src/mcp_types.rs`). Claude read-mostly seats: `--permission-mode dontAsk` ("auto-denies every tool call that would otherwise prompt you … the session never waits for input", code.claude.com/docs/en/permission-modes) with an allow list in the seat's settings. Not taken: Gas Town's `--dangerously-skip-permissions` / `--dangerously-bypass-approvals-and-sandbox` (`internal/config/agents.go:236,286`) and claude-squad's auto-Enter (`daemon/daemon.go:51`): they answer prompts for the human. |
| 2 | `squad dispatch` said "started" while Codex sat on its start screen | 10 min | Gas Town: wait for the agent's ready prompt (Claude `❯`, Codex `›`), then verify the turn started ("esc to interrupt") or the input line cleared, else resend (`internal/tmux/submit_verify.go`, `polecat/session_manager.go:890`). ccmanager's Codex detector (`src/services/stateDetector/codex.ts`). |
| 3 | False STALLED alarms while the tester waits on its own 17-min run | the lead reads process lists each time | Gas Town dropped pane-idle checks for structured signals: "fresh heartbeat — agent is alive, not stalled" (`witness/handlers.go`, `polecat/heartbeat.go`, `tui/feed/stuck.go`). squad: a seat that owns a live `squad heavy` run is busy; the run refreshes a heartbeat. |
| 4 | A hung run (no CPU, no output) holds the shared lock to the 20-min cap | up to 20 min + the queue | CircleCI `no_output_timeout` (default 10 min), Travis "no output … for 10 minutes" (docs); Bazel: the runner owns timeouts. squad: stop a run whose output and CPU time have not moved for `heavy_silent_minutes` (default 5), log `HUNG`. |
| 5 | Tasks under way at the switch (DONE-FOR-SWITCH) were refused by `squad dispatch` | 3 hand-sent dispatches | squad's own bug: any earlier event of a dev seat for the task counts as "under way". |
| 6 | A dev idle 14 min with ready work and no brief | 14 dev-min | Gas Town GUPP: "If you find work on your hook, YOU RUN IT" and push with `gt assign --nudge`; Claude agent teams: an idle teammate takes the next unblocked task. squad: the watcher tells the lead once when a dev is idle with no open task for `idle_minutes` (default 5). The lead still writes the brief and dispatches. |

## Scope
- In: seat arguments in the presets (reviewer: `-a never`, playwright off; observer: `dontAsk` + allow
  list); `update-conf` adds missing safe arguments to the matching seat lines; ready check and start
  check in `squad dispatch` (`DISPATCH_NOT_STARTED`); heartbeat and busy-while-heavy in the stall
  check; the no-output watchdog in `squad heavy` (`HUNG`); the contract exemption; the idle-dev line
  to the lead; README.
- Out: bypassing permissions or answering prompts for the human; auto-dispatch without the lead;
  containers (roadmap).

## Done when
- [x] Shipped presets and `update-conf`: the Codex reviewer starts with `-a never` and the playwright
      MCP server and plugin off; the observer starts with `--permission-mode dontAsk` and an allow list
      (read, read-only git, squad commands); dev and tester seats are unchanged.
- [x] `squad dispatch` sends only when the seat shows its ready prompt and no menu, and says "started"
      only when the pane shows a running turn or the task left the input line; otherwise it resends
      once, then logs `DISPATCH_NOT_STARTED` and fails.
- [x] A seat that owns a live heavy run is never STALLED; `squad heavy` refreshes
      `seats/<seat>.heartbeat`; STALLED uses the newest of its events, heartbeat and working time.
- [x] A heavy run whose output size and process-group CPU time do not change for `heavy_silent_minutes`
      is stopped as a group, logged `HUNG`, exits 124, and frees the lock; the 20-min cap stays.
- [x] A task with any earlier dev event (e.g. DONE-FOR-SWITCH) is dispatched without a contract; a
      dev idle with no open task for `idle_minutes` gives the lead one line; tests pass under bash 5 and 3.2.

## Sources (opened and read by the research agent, 13 Nov 2026)
- Codex: https://github.com/openai/codex (`codex-rs/core/src/mcp_tool_call.rs`, `codex-rs/config/src/mcp_types.rs`), https://learn.chatgpt.com/docs/config-file/config-reference
- Claude Code: https://code.claude.com/docs/en/permission-modes, https://code.claude.com/docs/en/permissions, https://code.claude.com/docs/en/agent-teams
- Gas Town: https://github.com/steveyegge/gastown (`internal/config/agents.go`, `internal/tmux/submit_verify.go`, `internal/witness/handlers.go`, `internal/tui/feed/stuck.go`, `internal/cmd/assign.go`)
- claude-squad: https://github.com/smtg-ai/claude-squad · ccmanager: https://github.com/kbwo/ccmanager
- Beads: https://github.com/steveyegge/beads · Agent mail: https://github.com/Dicklesworthstone/mcp_agent_mail_rust
- Cursor: https://cursor.com/blog/scaling-agents · Anthropic: https://www.anthropic.com/engineering/building-c-compiler
- CI: https://circleci.com/docs/reference/configuration-reference/, https://docs.travis-ci.com/user/common-build-problems/, https://bazel.build/reference/test-encyclopedia, https://vitest.dev/guide/reporters

## Assumptions & open questions
1. **Open decision for V!:** dev and tester seats keep today's permission mode (your Claude settings,
   auto mode); only the reviewer and the observer change. `dontAsk` for devs would turn every missing
   allow rule into a refusal; it needs a per-project allow list first.
2. Not verified live: an interactive Codex seat with `-a never` (only config parsing was tested).
3. For hive, the new seat arguments arrive through `update-conf` at the next `squad up`.

## Evidence (14 Nov 2026)
`bash test/smoke.sh`: 320 passed under bash 5 and /bin/bash 3.2.57; `shellcheck -S warning`: clean. Smoke: 'the reviewer starts with -a never', 'the observer's settings allow only its own folder and read commands', 'update-conf adds -a never to a Codex reviewer and dontAsk to an observer', 'dispatch refuses a seat that shows a menu instead of its prompt', 'dispatch sends once the seat is at its prompt and sees the turn start', 'a task stopped for a switch (DONE-FOR-SWITCH) goes on without a contract', 'a run with no output and no CPU is stopped as hung', 'a run that keeps printing is not hung', 'a seat with a live heavy run (fresh heartbeat) is not stalled', 'an idle dev with no task is told to the lead once'. Not verified live: a Codex seat with `-a never`; the ready-prompt marks on real panes.
