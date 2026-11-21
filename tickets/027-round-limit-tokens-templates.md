# 027 · The round limit is in code, tokens are measured per seat and task, hive's practices are in the templates
Status: Approved (V!, 21 Nov 2026: "make all the fixes and improvements asap")
Size: M (≤ 1 day)

## Goal
Fewer review rounds and a first answer to "what does a task cost". In hive 80 % of tasks
needed a fix round, the round limit existed only as text, and no token number per seat or
task exists (report ranks 8, 10 and 11).

## Scope
- In: `squad dispatch` (the round count), a new `squad tokens` command, `squad report`
  (one new column), `templates/roles/lead.md`, `templates/roles/dev.md`,
  `templates/roles/reviewer.md` (or the file that holds the reviewer's role),
  `templates/PROTOCOL.md`, the smoke tests, README.
- Out: models and effort per seat (report rank 13: after the numbers exist); prompt text
  in any measurement (numbers only); OpenTelemetry.

## Done when
- [ ] `squad dispatch` of round `round_limit + 1` of a task (default limit 5, a `team.conf`
      setting) is refused with a message, a `ROUND_LIMIT` event is logged and V! gets one
      notification that names the task and its review files.
- [ ] `squad tokens` prints, per seat and per task, the input, cache-read, cache-write and
      output token counts and the number of model calls, read from the seats' Claude Code
      session files (numbers only, no prompt text); a Codex seat shows its token counts
      when its session files hold them, else "not measured".
- [ ] `squad report` shows the tokens of each merged task.
- [ ] The templates say: a review finding names the class of the defect and the places,
      and the dev fixes the class; the reviewer checks correctness against the brief and
      skips style; a brief lists the consumers of a changed part; a dev runs the tests of
      the changed files (or the sample) and the full suite runs only in the candidate.
- [ ] `test/smoke.sh` passes, with a test for each item above that fails before the change.

## Plan
- Round count: from the `DISPATCH` events of the task in `events.log`.
- `squad tokens`: the session ids squad already records per seat; a task's window is from
  its `DISPATCH` to the next `DONE` of that seat; `jq` over the `usage` fields.
- Templates: short additions in the existing sections.

## Tests
One smoke test per "Done when" item; the token test uses a fixture session file.

## Assumptions & open questions
- Report decisions 9, 10 and 12: the recommended options. Decision 15 (which other hive
  practices move into the templates) stays open: V! approves them item by item.
