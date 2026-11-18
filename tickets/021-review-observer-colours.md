# 021 · The review and observer tabs show what each seat does now, in colour
Status: Approved (the owner, 18 Nov 2026: "ok")
Size: S (≤ 2 h)

## Goal
The owner opens the review or the observer tab and sees at once what each seat there works on, its result and
for how long, in the same colours as the sidebar and the report.

## Scope
- In: one status line per seat on top of the review tab (tester and reviewers) and of the observer tab: per seat the
  state mark, name and role in its colour, phase, ticket, title and time (the same line as the report's NOW).
  It refreshes every 20 s. The pane has one row per seat in that tab. In the mission layout (no review tab:
  the tester and reviewers are in the team tab), and after a resume that put those seats in another tab, the pane
  goes under those seats, in whatever tab they are.
- Out: the agents' own panes (squad does not draw inside them); new tabs; the HTML page.

## Done when
- [ ] The owner sees a live preview of both tabs in hive and says it is clear (before any merge).
- [ ] The line uses the report's NOW format and colours; NO_COLOR gives plain text.
- [ ] Smoke passes on `/bin/bash` 3.2 and in CI; shellcheck is clean.

## Plan
- bin/squad: `squad seats <role…>`: the NOW lines for those roles only (from `report_text`), live; a 3-row pane
  on top of the review and observer tabs at `squad up` and on resume.
- test/smoke.sh: the command prints only the asked roles.

## Tests
- Smoke: `squad seats tester reviewer` prints those seats' lines and no other.
- Preview in hive (read only) before the merge.

## Assumptions & open questions
- The pane height follows the number of seats in the tab, so every seat has its own line.
