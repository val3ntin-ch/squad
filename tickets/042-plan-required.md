# 042 · `plan required`: no task starts without the owner's approved plan
Status: Approved (val3ntin-ch, 23 Nov 2026: "ok all, only defer the sandbox one")
Size: S (≤ 2 h)

## Goal
squad's plan gate (proofs, GPT critique, a sealed approval) is skipped when a team has no
`PLAN.md`; hive never used it (0 approvals in 8,773 log lines). With `plan required` a team
cannot dispatch a first task until the owner approved a plan.

## Scope
- In: a `plan required|optional` setting (new teams: required; `update-conf` adds `plan
  optional` to existing teams so nothing stops them); `plan_gate`; README; smoke tests.
- Out (not in this ticket): the content of the plan step.

## Done when
- [ ] With `plan required` and no approved `PLAN.md`, a first dispatch is refused with the
      command that starts the plan.
- [ ] `squad new` writes `plan required`; `update-conf` writes `plan optional` into an
      existing team and says so.
- [ ] `test/smoke.sh` passes in CI, with a test for each item that fails before the change.

## Plan
- One setting read by `plan_gate`.

## Tests
Smoke tests.

## Assumptions & open questions
- Hive gets `plan optional` until the owner changes it.
