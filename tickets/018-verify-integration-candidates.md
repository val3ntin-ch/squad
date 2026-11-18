# 018 · Check integration candidates before merge

Status: Approved (the owner, 18 Nov 2026: "ok" to the recommended options: the gate runs locally in squad (A); running tasks are tested again before their next merge (B))
Size: M (≤ 1 day)

## Goal

Squad integrates the exact candidate that passed its required checks. The lead and owner can identify the review and test evidence for that candidate.

## Scope

- In: local candidate identity, tester checkout, required check receipts, task review identity, and local promotion. Update the role instructions that call these commands.
- Out: GitHub settings, production deployment, agent permissions, new storage services, provider telemetry, and a general workflow rewrite.

## Done when

- [ ] The candidate runner uses a clean checkout of the declared full SHA, even when the caller starts in a different worktree. Its receipt records the same SHA and the result of each required check.
- [ ] The runner writes the receipt itself (full SHA, the exit code of each required check). `squad done … PASS`
      reads that receipt and does not trust its caller; a PASS without a matching receipt is refused.
- [ ] Candidate `PASS` requires every required check. The receipt matches the candidate SHA and hashes of the approved contract and check plan.
      A pending, unavailable or inconclusive row, a missing candidate brief, or a report whose `RESULT:` line
      disagrees blocks the PASS. The ticket names where the candidate brief lives.
- [ ] The tester's checkout is refused when it is dirty; events.log records the full SHA.
- [ ] Integration advances to the tested candidate only with approvals for the exact task heads. The update checks the expected base atomically and stops if it moved.
- [ ] The smoke checks pass on macOS Bash 3.2 and CI's Linux shell. `shellcheck -S warning bin/squad install.sh test/smoke.sh` passes.

## Plan

- Add the three failing fixture cases from the audit to `test/smoke.sh`. Add a passing case and cases for a changed base and a changed task head.
- In `bin/squad`, give the candidate a full commit identity and a snapshot of its required checks. Check the checkout before the tester starts.
- Record check results in a local runner receipt. Check the receipt before accepting candidate `PASS`.
- Check the current base, candidate, and reviewed task heads before integration advances. Stop if any value differs.
- Update the lead and tester templates and the README to describe the candidate command and the recovery path. Run the repository checks.

## Tests

- A synthetic tester runs from a different worktree. The output SHA equals the candidate receipt SHA.
- A missing receipt, skipped check, or nonzero result blocks the candidate. A change to the candidate, contract, or check plan invalidates the receipt.
- A task with no review or a changed head stays out of integration. A base move during promotion stops the update. Successful promotion produces the tested commit SHA.
- Run `bash test/smoke.sh` and `shellcheck -S warning bin/squad install.sh test/smoke.sh`. Repeat smoke with Bash 3.2 on macOS.

## Assumptions & open questions

- **Open decision for V!** Option A adds the local candidate gate in this ticket. Option B moves the evidence and promotion gate into hosted CI first. Recommend A for the current setup. A later ticket can add independent release enforcement.
- **Open decision for V!** For work already in progress, either retest before its next integration or keep the old path temporarily. Recommend retest so every new integration has evidence.
- A local receipt prevents workflow mistakes. Independent authority for release approval belongs in the delivery pilot.
- [Audit findings](../docs/research/2026-11-17-squad-factory-audit.md)
- Verification of the audit (17 Nov 2026): [audit check](../docs/research/2026-11-17-squad-factory-audit-verification.md).
  It added the receipt authority, the untested rows, the brief location and the dirty checkout to "Done when".
