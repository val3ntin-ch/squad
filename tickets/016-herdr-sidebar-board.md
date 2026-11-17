# 016 · herdr's own Agents sidebar shows the squad: role, ticket, phase, and who needs the owner
Status: Draft — waiting for approval
Size: M (≤ 1 day)

## Goal
The owner sees at a glance, in herdr's own Agents sidebar, what each seat does (role, ticket, phase,
task) and which seat needs them, with no drawn screen of squad's own. Every part is proven live on
herdr 0.9.3 (report: reports/Herdr agent UI for squad.md); squad's alerts are checked, not fire and forget.

## Scope
- In:
  - `seat_meta`: at each dispatch, DONE, test result, verdict, merge and resume, squad sends herdr
    `pane report-metadata` for the seat (source `squad:seat`): display name, the task as the pane title,
    a phase label for working, "NEEDS YOU" for blocked, and tokens `role`, `ticket`, `task`, `phase`.
    squad never calls `report-agent` on a real Claude, Codex or OpenCode seat (herdr owns its state).
  - The team's step and progress as a workspace token (Spaces row).
  - `templates/herdr-sidebar.toml`: the sidebar rows and role colours, for the owner to paste into
    herdr's config; `squad doctor` says when the rows are missing. squad never edits the owner's config.
  - `agent.view.set` over herdr's socket at `squad up` and on resume (only squad's seats, the ones that
    need the owner first); cleared at `squad down`. A small `python3` helper sends the socket call.
  - `v_notify` reads herdr's answer: `disabled`, `rate_limited` or `no_foreground_client` is written to
    events.log and the strip; at most one notification a second; never a retry loop.
- Out: a herdr plugin, popups, the tab bar line, an event-driven watch, the Herdr App, Kitty images,
  the herdr upgrade to 0.9.5 (each its own decision later).

## Done when
- [ ] In a throwaway herdr session with a second herdr client attached, the captured sidebar text shows,
      for each seat: its name, role, ticket and phase; a blocked seat reads "NEEDS YOU" and is listed first;
      a non-squad agent is not listed. The owner sees this preview before anything goes to hive.
- [ ] After a dispatch, a DONE, a test result and a verdict, `herdr pane get` shows the new tokens for that
      seat (smoke tests with the herdr stand-in check every call).
- [ ] `squad up` and a resume send the view and every seat's tokens again (a herdr restart loses them).
- [ ] `v_notify` logs a `disabled` or `rate_limited` answer and sends at most one notification a second
      (smoke tests feed both answers).
- [ ] `templates/herdr-sidebar.toml` passes `herdr config check`; `squad doctor` reports missing rows.
- [ ] Smoke tests pass; shellcheck is clean; bash 3.2.

## Plan
- bin/squad: `seat_meta <seat>` from the existing state points (dispatch, done gate, merge, resume);
  `team_meta` for the workspace token; `herdr_view set|clear` through a `python3` socket helper;
  `v_notify` parses the reply and coalesces.
- templates/herdr-sidebar.toml: rows for the Agents and Spaces sections (only the tokens and colours the
  live render proved).
- squad doctor: checks the rows are in herdr's config.
- Preview: a script that builds a scratch herdr session, attaches a second client, runs the calls and
  captures the sidebar as text; then shows it to the owner.

## Tests
- Smoke: every `report-metadata` and `agent.view.set` call is in the stand-in's log with the right
  tokens; `v_notify` with `disabled` and `rate_limited` replies.
- Live preview in a scratch session (the owner looks before hive gets it).

## Assumptions & open questions
- Open decision for the owner: who writes the sidebar rows into herdr's config. Recommendation: squad ships
  the snippet, the owner pastes it (or says "paste it for me" once); squad never edits it silently.
- Open decision for the owner: python3 as a dependency for the socket call. Recommendation: yes (macOS has it;
  herdr's own Claude hook uses the same method). Without it, everything works except the filtered, sorted list.
- Fact: one Agents view per herdr server; a second team in the same herdr session would replace it.
- Not proven: herdr reloading new sidebar rows without a restart (`herdr server reload-config` applied the
  toast setting live; rows are tested in the preview).
