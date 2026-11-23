# 033 · One dev per task; a sent-back task is reviewed again; the observer rests when nothing happened
Status: Approved (val3ntin-ch, 23 Nov 2026: "ok all, proceed")
Size: M (≤ 1 day)

## Goal
Close three gaps that the software-factory audit of 23 Nov 2026 found in hive's event log
(val3ntin-ch, 23 Nov 2026: "I want all to be fixed"; for the failed batch: "automated and not man in
the middle"). Squad's code enforces each rule; no rule waits for val3ntin-ch.

Measured on hive (event log, 13 to 23 Nov, 120 tasks):
- One task went to two devs for 5 tasks, 3 of them since 22 Nov 02:34. T-180: dev-c got it,
  dev-a got it 80 s later, dev-c was flagged stalled 19 min later. Only a sentence in
  `lead.md` forbids it.
- T-182 failed in batch 119 and was sent back. The lead approved the fix 12 s after DONE,
  against the review of the old commit. Batch 121 failed again and held the test lock for
  31 min. Before PR #28 one task was in 4 failed batches.
- The observer made 43 passes in the 14 h after the last work event (one each 20 min),
  because 125 open tasks count as work.

## Scope
- In: `squad dispatch` to a dev seat; `squad done lead <task> APPROVE` and `squad candidate`
  for a task that was sent back; `observe_tick`; the role files of the lead and the
  reviewer; smoke tests; README.
- Out (not in this ticket): the next task for a free dev (ticket 034); the review round
  limit (it stays 5, and the new review rounds count for it); the heavy lock; ticket 031.

## Done when
- [x] `squad dispatch <dev> <task>` is refused while another dev seat holds that task (a
      dispatch with no DONE, BLOCKED or WITHDRAWN after it); the message names the holder.
      `squad dispatch --reassign` moves the task and logs `REASSIGNED`.
- [x] After a task is sent back from a failed batch, `squad candidate` refuses that task
      until a reviewer verdict APPROVE names the task's current commit. The dev's DONE notice
      tells the lead to dispatch the reviewer.
- [x] A team with no reviewer seat keeps today's behaviour (the lead reviews), and the
      refusal message of the item above says so.
- [x] The observer makes no timed pass when the event log has no new work event since its
      last pass; its next pass comes with the next work event or the next alarm of the watch
      (a stall, a blocked or dead seat), as before.
- [ ] `test/smoke.sh` passes in CI, with a test for each item above that fails before the
      change.

Evidence for the ticked items: the 39 checks of the block "033" in `test/smoke.sh`; run alone
they pass on this branch, and the 22 that test new behaviour fail on `main`. Two review rounds
(GPT and Claude) found 9 real defects; each is fixed with a check in that block.

Not run: the real trial with live agents for the sent-back case (planned in "Tests"). The rule
reads only the event log and the task branches, and types nothing into a seat, so the checks
with the stand-in herdr cover it; the CI run covers the whole suite.

## Plan
- Holder of a task: read from `events.log` the newest `DISPATCH` to a dev seat for the task
  and the verdict lines after it; refuse in `cmd_dispatch` before the queue step.
- Sent-back mark: `candidate_sent_back` already records it; `squad candidate` compares the
  task's head with the `head=` of the newest reviewer `APPROVE` line when the mark is set.
- `observe_tick`: count work events (not `OBSERVE`, `IDLE`, `STALLED`) after `.last-pass`.
- Role files: one line each for the lead and the reviewer on the sent-back review.
- Tests with the stand-in herdr of `test/smoke.sh`; real trial on the throwaway team for the
  sent-back case.

## Tests
One smoke test per "Done when" item, each failing before the change; one real trial for the
sent-back case (a batch fails, the task comes back, the batch is refused, the reviewer
approves, the batch is accepted).

## Assumptions & open questions
- "Automated" means: squad refuses and tells the lead what to do next, and the lead (an
  agent) does it. Squad itself does not start the reviewer, because only the lead starts a
  dispatch (val3ntin-ch's rule of 18 Nov).
- While val3ntin-ch sleeps: a task that reaches review round 5 stops and waits for val3ntin-ch; every other
  task goes on. This is the existing round limit.
- Decided by val3ntin-ch (23 Nov 2026): when the reviewer seat exists but is down (dead, sign-in, a
  dialog), the sent-back task waits for the reviewer; the lead does not review in its place.
  A task that waits does not stop the other tasks.
- Decided by val3ntin-ch (23 Nov 2026): after 5 review rounds a task waits for val3ntin-ch, as today.
