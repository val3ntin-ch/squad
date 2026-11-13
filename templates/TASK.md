# T-000: <short title>

This file is the whole brief. Read it and the SPEC sections it names. Nothing else is needed.

- Owner: dev-a
- Branch: `task/T-000`, from the integration branch
- Depends on: -
- SPEC sections: <Design: …, Visual check>

## Goal

<Two or three sentences: what exists when this task is done, and why it matters.>

## Files (only these may change)

- `src/...`
- `src/.../__tests__/...`

## Acceptance

Each row is checked by the dev, by the tester (against its contract `reports/<ID>-contract.md`) and by the reviewer or the lead. Each needs evidence and one result: pass, fail, pending, unavailable or inconclusive. `squad done` refuses DONE or PASS while a row is missing or `fail`.

| # | Requirement | How to check it |
|---|---|---|
| 1 | <a behaviour someone can check by running something> | `<command>` or <what to measure> |
| 2 | <an edge case that must be handled> | |
| 3 | <a visual requirement: the expected value, the size, the state> | <where to look, what to compare with> |

## Dev check

`<a light command for this task's own files; squad done runs it before it accepts DONE; "-" for none>`

## Check command

`<the exact command the tester runs for this task, through squad heavy>`

## Consumers to run

<The tests and files outside this task's files that use what it changes, and the command that runs them (for example `vitest related --run <changed files>`), plus names read as text that the import graph cannot see. "None" when nothing outside uses it.>

## If a check outside your files breaks

<What the dev does: fix it inside these files, add the file to the scope (named here), or report BLOCKED. Write the rule here, so the dev does not guess.>

## Red run (bug tasks)

<The command that fails on the base commit because of the bug, and how it fails. "-" for a task that is not a bug fix.>

## Visual check

<The page or screen to open, the sizes and modes to check, and the reference to compare with. "None" when the task has nothing to look at.>

## References

- <the file, library doc or official page that decides an open detail>

## Notes

<Anything the dev needs that is not in the SPEC. Otherwise leave empty.>
