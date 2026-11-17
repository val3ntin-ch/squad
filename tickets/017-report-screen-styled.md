# 017 · The report tab: what each seat does now, in colour, and what waits for the owner
Status: Approved (the owner, 17 Nov 2026: "looks good the new preview")
Size: S (≤ 2 h)

## Goal
The owner opens the report tab and sees at once what each seat works on, what waits for them, and
what went wrong. Today the tab is plain grey text, and the observer repeats the same line for every pass.
The owner, 17 Nov 2026: "should be more styled … to see easy what it's working on … it's too generic".

## Scope
- In (`report_text` in bin/squad, the terminal view only):
  - A header band: team, `x/y merged`, the lock, how many seats need the owner.
  - NOW, first: one line per seat: a state mark (● working, ◆ needs you, ○ idle), the name and role
    in the role colour of the sidebar (ticket 016), the phase in plain words in a state colour
    (green passed/merged/approved, red failed/changes/needs you, yellow waits, blue at work),
    the ticket, the task title, and the time since the last step. A finished seat follows what
    happened to its task later (the same rule as the sidebar).
  - WAITS FOR <OWNER>: each item to test: the id in bold yellow, its text, then "look:" on its own line.
  - OBSERVER: only the newest pass; repeated identical passes fold into one line ("the same for 8 passes").
  - TASKS: the status in colour (merged green, open blue); a wait of 60 min or more in orange; a FAIL in red.
  - EVENTS: time, seat in its role colour, the event in a state colour; the observer's routine passes hidden.
  - Lines are cut at the pane width with "…", never inside a letter.
- Out: the HTML page (`o`), the sidebar, a new screen or tab of squad's own (the owner reverted those on
  16 Nov 2026), mouse or keyboard navigation.

## Done when
- [ ] The owner looks at the preview tab "report (new)" in hive and says it is clear (the owner tests visual items).
- [ ] With no colour support (`NO_COLOR=1` or not a terminal) the report prints the same lines with no escape codes.
- [ ] Smoke: the NOW line of a seat shows its name, role, phase, ticket and title; a merged task shows MERGED
      for its dev; repeated observer passes fold into one line; OBSERVE events are hidden.
- [ ] Smoke passes (also `/bin/bash` 3.2); shellcheck is clean.

## Plan
- bin/squad: rewrite `report_text`; move the "follow the task" rule from `ui_sync` into `seat_phase`, so the
  sidebar and the report agree.
- test/smoke.sh: the checks above, on the herdr stand-in.

## Tests
- Smoke: `squad report --live` with `perl alarm` for one frame; `NO_COLOR=1` output has no `\033`.
- Preview: the tab "report (new)" in hive runs the new view on hive's real data (read only).

## Assumptions & open questions
- Assumption: the colours are the sidebar's (Catppuccin Mocha), so a role has the same colour everywhere.
- The preview runs from a scratch copy; nothing in hive changes. The tab closes after the owner's answer.
