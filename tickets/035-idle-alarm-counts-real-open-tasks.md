# 035 · The idle alarm counts only open tasks and names the tasks that wait for the owner
Status: Approved (val3ntin-ch, 23 Nov 2026: option "b")
Size: S (≤ 2 h)

## Goal
When a dev has had no task for 30 minutes, the owner gets a notification with the number of
open tasks. On hive it said "124 open task(s)" while only 21 rows were not merged and none
was ready (measurement in ticket 034). After this ticket the number is right, and the owner
sees which tasks wait for the owner's decision, so the owner knows what unblocks the team.

## Scope
- In: the open-task count of the idle notification to the owner and its event line; smoke
  tests; README.
- Out (not in this ticket): when the alarm fires (`idle_minutes`, `idle_owner_minutes`); the
  lead's 5-minute line; the format of TASKS.md.

## Done when
- [x] A row of TASKS.md counts as open unless the first word of its status cell is `merged`,
      `done`, `closed` or `not needed` (in any case, also inside `**…**` or with more text
      after it); "unmerged" or "reopened (was merged …)" stay open.
- [x] The notification and the IDLE event line name the open rows that wait for the owner
      (a status with "waits for", "open decision" or "decision for"), by task ID.
- [x] With no open row the owner is not told (as before).
- [ ] `test/smoke.sh` passes in CI, with a test for each item that fails before the change.

Evidence: the three "035" checks in `test/smoke.sh` (they fail on `main`: the alarm said 8
open tasks where 3 are open). On hive's real TASKS.md the new count is 14 (squad said 125),
and the rows that wait for val3ntin-ch are T-136, T-141 and T-158.

## Plan
- One awk over TASKS.md prints the open count and the IDs that wait for the owner.
- The notification body and the event line add "<n> wait for <owner>: <IDs>" when n > 0.

## Tests
Smoke: a TASKS.md with hive's real status forms (`**merged** 21 Nov …`, `merged (CANDIDATE-1)`,
`**done** …`, `**closed** …`, `**not needed**`, `todo; waits for D-100`, `todo`, a stopped row
with an open decision): the count is 3 and two IDs are named.

## Assumptions & open questions
- "Waits for the owner" is read from the status words that hive's lead uses today; a row
  written another way is counted as open but not named.
