# 002 · QA and review: GPT reviewer, contract first, five result states, done gate
Status: Approved (V!, 13 Nov 2026)
Size: M

## Goal
Fewer review rounds and no claim of "verified" without evidence: the acceptance contract is
fixed before code, a second vendor reviews every diff with a fresh context, and `squad done`
refuses work that is not proven.

## Scope
- In: default preset with a GPT reviewer seat; tester checks each brief before dev starts;
  five result states; `squad done` gate; consumers to run; red run for bug tasks; class
  findings; fix loop policy; candidate batching in the templates.
- Out: a second tester seat (it competes for the one heavy lock); the observer (003).

## Done when
- [ ] `presets/default.conf` has `seat rev-gpt codex reviewer dev-a,dev-b,dev-c -m <model>`;
      the lead reviews after the GPT verdict and adjudicates each finding before merge.
- [ ] TASK.md has "Consumers to run", "If a check outside your files breaks", and for a bug
      task "Red run on the base commit"; each acceptance row has a result in one of
      pass / fail / pending / unavailable / inconclusive.
- [ ] Before a task goes to a dev, the tester reviews its acceptance table and writes
      `reports/<ID>-contract.md` (thresholds and exact commands); the lead dispatches only
      after it. `squad dispatch` refuses a dev task with no contract file.
- [ ] `squad done <dev> <ID> DONE` refuses (exit 1, says why) when the report misses a row
      of the brief's acceptance table, or when the brief's check command fails.
- [ ] Role text: a review writes one finding per class with all places; re-review reads only
      the fix diff; round 4+ goes to a fresh dev with a higher model (`escalate_model` in
      team.conf); after the cap the task goes to READY.md as "Open decision for V!".
- [ ] `bash test/smoke.sh` and `shellcheck` pass.

## Plan
- `presets/*.conf`, `templates/TASK.md`, `templates/roles/{lead,dev,tester,reviewer}.md`,
  `templates/PROTOCOL.md` ("How much to test", candidates with bisect).
- `bin/squad`: gate in `cmd_done` (parse acceptance rows of the brief and the report; run
  the `## Check command` line through `squad heavy` only when it is marked heavy).
- `cmd_dispatch` (from 001): contract-file check for dev seats.

## Tests
- smoke: done refuses a report with a missing row; accepts a full one; refuses on a failing
  check command; accepts with exit 0.
- smoke: dispatch refuses without `<ID>-contract.md`.
- smoke: default preset parses and has a codex reviewer.

## Assumptions & open questions
1. **Open decision for V!:** the GPT model name. Fixtures say `gpt-6.1-sol`, not verified on
   your Codex 0.161.0. I will read `codex` help and `~/.codex/config.toml` and propose it.
2. **Open decision for V!:** does GPT replace the lead's review (today's reviewer seat) or
   come before it (both)? Recommended: both — GPT first (cheap, independent), the lead
   adjudicates and does the visual check.
3. Assumption: running the check command in `squad done` is a "light" run; a brief can mark
   it heavy, then it goes through `squad heavy`.
