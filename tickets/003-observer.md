# 003 · Observer seat and tab: stuck seats, timeline, suggestions
Status: Approved (V!, 13 Nov 2026)
Size: M

## Goal
V! opens one herdr tab, `observer`, and sees what happens now, what went wrong, what it
cost, and what to change — written to files that are easy to follow later. The hive run
had an observer by hand; v2 ships it.

## Scope
- In: an `observer` seat (read-only, Claude Sonnet, low effort) in its own herdr tab;
  stuck-seat detection in the script; files under `.team/observer/`; the Observer and
  Timeline tabs of `squad report`.
- Out: the observer never prompts a seat and never edits code or team files other than
  its own (the lead acts on its points). Decisions page (004).

## Done when
- [x] `squad up` opens the tabs `team · review · changes · observer · report`. The `observer`
      tab has the observer seat on top and `squad watch --observe` below. The `report` tab runs
      `squad report --live`: the same content as the HTML page, in the terminal, refreshed
      every 20 s (Now, Suggestions, Decisions, Timeline, QA, Cost); `o` opens the HTML page.
      squad starts each observer pass itself (after a merge or new trouble, and at least every
      `observe_minutes`, default 20), by a prompt from the watch loop — no CronCreate inside the
      observer session, so passes survive a restart and have no 7-day limit.
- [x] The watch pane flags a seat as `dead` (pane gone), `login` (pane shows `/login`
      or `API Error`), `blocked`, or `stalled` (task dispatched, no commit, report or pane
      change for `stall_minutes`, default 15).
      A seat in trouble writes one line to `events.log` (`STALLED`, `DEAD`, `LOGIN`, `BLOCKED`)
      and one line to the lead, once per seat and kind. "Stalled" means: an open task and its
      agent not working for `stall_minutes`.
- [x] The observer writes, every pass (the lead's events wake it; at most every 20 min):
      `.team/observer/NOW.md` (what is wrong now and what it costs, in minutes),
      `.team/observer/SUGGESTIONS.md` (ranked: problem, evidence, proposed change, file,
      minutes saved; status open / adopted / rejected with reason), and appends
      `.team/observer/passes.log`.
      The lead reads NOW.md at every merge and marks each suggestion adopted or rejected
      in SUGGESTIONS.md (role text).
- [x] `squad report` shows the Observer tab (NOW and SUGGESTIONS) and the Timeline tab
      (events.log per task: dev, test, review, merge minutes).
- [x] `bash test/smoke.sh` and `shellcheck` pass.

## Plan
- `templates/roles/observer.md` (from the hive observer's practice: numbers, basis, source,
  "Decision for V!" when it touches V!'s files).
- `bin/squad`: `observer` role in load_conf and roster; `make_layout` adds the tab;
  `watch_once --observe` with stall detection (herdr `agent list`, `pane read` tail,
  `git log -1` per worktree, report mtimes).
- `cmd_report` part 1: Observer and Timeline tabs (static HTML, inline CSS, light/dark).
- presets: observer seat in `default` and `large`.

## Tests
- smoke: layout creates the `observer` tab with the stand-in herdr.
- smoke: stall detection — a dispatched task with no change past the limit gives one STALL
  line and one lead message; a `/login` pane text gives `login`.
- smoke: `squad report` builds an HTML file that contains the NOW and SUGGESTIONS text and
  one timeline row per task from a fixture events.log.

## Assumptions & open questions
1. Assumption: Sonnet, low effort, is enough for the observer (it reads files and panes).
2. The report page is opened by V! in a browser (`open .team/report.html`); no server.

## Evidence (13 Nov 2026)
`bash test/smoke.sh`: 234 passed under bash 5 and under /bin/bash 3.2.57; `shellcheck -S warning`: clean. smoke: 'the tabs come in order: review, changes, observer, report', 'the report gets its own tab, live', 'the watcher starts the observer's first pass', 'a merge starts the next pass', 'a seat with an open task and no work is stalled', 'the stall is logged once and the lead is told', 'a sign-in error is named', 'the page shows the observer's now and suggestions', 'the timeline has the task's minutes'. Not verified with a real observer seat writing its files.
