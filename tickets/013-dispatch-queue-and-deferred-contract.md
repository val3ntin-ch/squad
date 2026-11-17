# 013 · Dispatch waits for a busy seat; a dev starts while the tester runs
Status: Approved (the owner, 16 Nov 2026: "make the fixes")
Size: S (≤ 2 h)

## Goal
Devs stop waiting with no task. The observer measured dev-b idle 47 min and dev-a 7 min on
16 Nov: a dev waited for a contract, the contract waited for the tester, and the tester was in a
45-min candidate run; `squad dispatch` to the busy tester failed (observer S-39, S-12, S-47).

## Scope
- In: S-39 (dispatch to a busy seat queues and sends when the seat is free); S-12 (a seat that is
  not at its prompt because it went back to work is queued, not refused); S-47 (while the tester is
  at work, a dev starts on the brief; squad queues the contract; the lead sends its notes as a RULE line).
- Out: any change to the tester's own runs or the candidate process.

## Done when
- [x] `squad dispatch` to a working seat returns at once with "queued", logs DISPATCH_QUEUED, and sends
      the task when the seat is free (smoke: "dispatch to a busy seat queues it…", "the queued task is sent…").
- [x] A queued dispatch that fails or waits more than 2 h tells the lead (one line in its pane).
- [x] With the tester at work, a dev dispatch without a contract starts and logs CONTRACT_DEFERRED; with
      the tester idle the contract still comes first (smoke: "a dev starts without a contract…", "with an idle tester…").
- [x] Smoke tests pass; shellcheck is clean.

## Assumptions
- "At work" means herdr reports the tester as working.
