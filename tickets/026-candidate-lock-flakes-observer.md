# 026 · Candidate runs lose less time: one number one commit, logs kept, a flake rule, the lock wait logged
Status: Approved (V!, 21 Nov 2026: "make all the fixes and improvements asap")
Size: M (≤ 1 day)

## Goal
The candidate step and the test lock stop losing time for reasons that are not product
defects. In hive, 16 of 50 candidate runs failed (8.0 h), the run log was deleted, one
number meant two commits, the wait for the lock could not be measured, and 372 of 588
observer passes ran while the team had no work (report ranks 4, 5, 6 and 9).

## Scope
- In: `squad candidate`, `squad heavy` (the lock, `--batch`), the candidate receipt, the
  observer timer in `squad watch`, the smoke tests, README, `templates/PROTOCOL.md`.
- Out: `squad merge` and its checks (unchanged); a second test lane; any change to which
  checks a team runs.

## Done when
- [ ] `squad candidate <N>` refuses a number that already has a candidate commit or a
      receipt, and names the next free number.
- [ ] A candidate batch keeps one log file per step beside the receipt
      (`.team/receipts/CANDIDATE-<N>/step-<i>.log`), also after a failure.
- [ ] With `flake_rerun 1` (the default) a failed batch step is run once more alone; when
      it passes, the batch goes on, the receipt names the step as a flake, a `FLAKE` event
      is logged and one line is added to `.team/flakes.log`; with `flake_rerun 0` any
      failure fails the batch, as today.
- [ ] A seat that waits for the heavy lock logs `HEAVY_WAIT` when it starts to wait, and
      `HEAVY_START` carries the seconds waited.
- [ ] The observer gets no pass prompt while no task is open (no dispatch without a merge
      or a withdrawal, and no candidate run); the first event after that starts the timer
      again.
- [ ] `test/smoke.sh` passes, with a test for each item above that fails before the change.

## Plan
- `cmd_candidate`: the used-number check before any git change.
- `cmd_heavy --batch`: write each step's output to its log file; on a failed step, the
  rerun rule; the receipt gets a `flakes` field.
- `cmd_heavy`: the two wait events around the existing wait loop.
- `observe_tick`: the open-work test before the pass prompt.

## Tests
One smoke test per "Done when" item.

## Assumptions & open questions
- Report decision 8: option (b) is built (rerun the failed step alone once and record it).
  Option (c) (accept only when the step also passes on the integration branch with the
  same test count) is not built: open decision for V!.
- Report decision 14: option (b).
