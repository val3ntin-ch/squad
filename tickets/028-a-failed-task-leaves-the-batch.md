# 028 · One task that fails leaves the candidate; the other tasks still merge
Status: Done — awaiting PR review
Size: M (≤ 1 day)

## Goal
A candidate that fails because of one task does not cost the whole batch. In hive on
21 Nov, 11 of 19 candidate runs failed; each failure cost 20 to 30 minutes of the one
test lock, and every task of the batch waited for a new candidate.

## Scope
- In: `squad candidate`, `squad heavy --batch` (the receipt), a new `squad candidate
  CANDIDATE-<n> --without <task>` form, `templates/roles/lead.md`,
  `templates/roles/tester.md`, the smoke tests, README.
- Out: `squad merge` and the conditions it checks (a merge still needs a PASS receipt for
  the exact commit); which checks a team runs; automatic choice of the failing task (the
  tester names it; squad does not guess).

## Done when
- [ ] A failed candidate's receipt folder names the failed step, its exit code and its log
      file, and `squad done tester CANDIDATE-<n> FAIL --task <ID>` records the task the
      tester holds responsible (event `CANDIDATE_FAIL task=<ID>`).
- [ ] `squad candidate CANDIDATE-<m> --from CANDIDATE-<n> --without <ID>` builds the next
      candidate from the same approved commits without that task, in one command, and
      logs which tasks it carries.
- [ ] The task that was left out is open for its dev again (its state is "sent back", the
      lead gets one line that names the step log), and the other tasks need no new review.
- [ ] `test/smoke.sh` passes, with a test for each item above that fails before the change.

## Plan
- The receipt folder (ticket 026) already keeps one log per step: add a `failed` line.
- `cmd_done`: the `--task` option for a candidate FAIL.
- `cmd_candidate`: `--from` reads the task list of the earlier candidate's CANDIDATE event.
- Role files: the tester names the task from the failing step's log; the lead rebuilds
  without it at once.

## Tests
One smoke test per "Done when" item.

## Assumptions & open questions
- Built after tickets 023 to 027 are merged (it changes the same functions).

## Verification
Two reviewers (GPT and Claude) on the full diff, findings fixed with tests; one real trial on a throwaway team (real git, real seats, a read-only `gh` call), 22 Nov 2026.

| Item | Result | Evidence |
|---|---|---|
| The receipt names the failed step, its exit code and its log; `FAIL --task <ID>` records the task | PASS | smoke "028: the receipt of a failed candidate names the failed step…", "028: the tester's FAIL records the task…"; real trial 6 (check 1) |
| `squad candidate … --from … --without <ID>` builds the next candidate in one command | PASS | smoke "028: one command builds the next candidate…"; real trial 6 (check 2: built, checks passed, merged) |
| The task left out is open for its dev again; the others need no new review | PASS | smoke "028: the task that was left out is sent back, with the step log", "028: the other tasks need no new review"; real trial 6 (the task was dispatched again, not refused by the round limit) |
| `test/smoke.sh` passes | PASS | 940 passed, 0 failed (bash 5 and bash 3.2) |
