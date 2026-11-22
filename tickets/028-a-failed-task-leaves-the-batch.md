# 028 · One task that fails leaves the candidate; the other tasks still merge
Status: Approved (V!, 21 Nov 2026: "do all 3")
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
