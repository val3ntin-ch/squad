# 029 · A fast gate for each candidate, the full suite once a night; squad reads the night's result
Status: Done — awaiting PR review
Size: S (≤ 2 h) for squad; the workflow is the team's own task

## Goal
The one test lock of the machine stops being the team's queue, at no cloud cost. In hive
on 21 Nov the lock was held 17.2 of 18.6 hours, 84 % of it by Storybook browser tests, and
11 of 19 candidates failed. V! decided (21 Nov): each candidate runs only fast checks
(lint, types, build, unit tests, the Storybook tests of the changed components); the full
suite runs once a night in GitHub Actions, and its failures become fix tasks.
A full run of every candidate in CI was refused: about $110 to $290 a month (GitHub's
price page, 21 Nov 2026: Linux 2-core $0.006 a minute; estimate of the minutes).

## Scope
- In: `squad nightly` (read the newest scheduled workflow run of the integration branch
  through `gh`, print its result, log `NIGHTLY PASS|FAIL`, tell the lead and notify V! on
  a failure, with the failed jobs); `templates/roles/lead.md`, `templates/roles/tester.md`
  and `templates/PROTOCOL.md` (fast gate per candidate, full suite at night, a failure
  becomes a fix task); a workflow example in the README; the smoke tests.
- Out: the project's own workflow file and check lists (the team writes them); pushing
  candidate branches; `squad merge` and its conditions.

## Done when
- [ ] `squad nightly` prints the newest scheduled run of the workflow (date, the workflow's commit,
      result, failed jobs with their URLs) and logs one `NIGHTLY` event per run.
- [ ] `squad watch` runs that check once after each new scheduled run: on FAIL the lead
      gets one line and V! one notification; on PASS only the event.
- [ ] With no `gh`, no workflow or no run, `squad nightly` says so and exits 0; the watch
      stays silent.
- [ ] The role files and PROTOCOL describe the fast gate and the nightly full run.
- [ ] `test/smoke.sh` passes, with a test for each item above that fails before the change.

## Plan
- `gh run list --workflow "$NIGHTLY_WORKFLOW" --event schedule --limit 1 --json …` (no `--branch`: GitHub records a
  scheduled run under the default branch, whatever ref the workflow checks out), then
  `gh run view <id> --json jobs`; a stand-in `gh` in the smoke tests.
- A setting `nightly_workflow <file name>` (empty: off).

## Tests
One smoke test per "Done when" item.

## Assumptions & open questions
- Built after tickets 023 to 028 are merged.
- Hive applies the decision at once through its own rules; squad's part only reports.

## Verification
Two reviewers (GPT and Claude) on the full diff, findings fixed with tests; one real trial on a throwaway team (real git, real seats, a read-only `gh` call), 22 Nov 2026.

| Item | Result | Evidence |
|---|---|---|
| `squad nightly` prints the newest scheduled run and logs one `NIGHTLY` event per run | PASS | smoke "029: squad nightly prints the date, the commit, the result and the failed jobs…"; real trial 6 (a real scheduled run read with the real `gh`, one event, none on the second call) |
| The watch checks once per new run; FAIL: one line to the lead and one notification; PASS: the event only | PASS (the PASS path on stand-ins only) | smoke "029: the watch checks a new scheduled run once", "029: on FAIL the lead gets one line…"; real trial 6 (check 6, FAIL path) |
| No `gh`, no workflow or no run: says so, exits 0, the watch stays silent | PASS | smoke "029: with no gh…", "029: with no scheduled run…"; real trial 6 (no remote, unknown workflow, no setting) |
| The role files and PROTOCOL describe the fast gate and the nightly run | PASS | smoke "029: the role files and PROTOCOL describe the fast gate and the nightly full run" |
| `test/smoke.sh` passes | PASS | 940 passed, 0 failed (bash 5 and bash 3.2) |
