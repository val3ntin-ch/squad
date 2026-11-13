# 005 · Learning and cost: compound step, converge, cost log, rule budget
Status: Approved (V!, 13 Nov 2026)
Size: S

## Goal
Each run makes the next one better and cheaper, and V! can see what a run cost.

## Scope
- In: compound step and converge pass in the lead's finishing steps; per-task cost in the
  Cost tab; a rule that each new protocol rule names the loss it removes.
- Out: automatic edits to squad itself (the lead proposes; V! approves).

## Done when
- [ ] Lead "Finishing": a converge pass (compare the integration branch with SPEC and every
      acceptance table; missing work becomes new briefs) before READY.md.
- [ ] Lead "Finishing": `.team/LESSONS.md` — each finding that came back twice becomes one
      proposal: a lint rule or test (shown to fail on the defect), or a template line, with
      the file to change. READY.md links it.
- [ ] `squad report` Cost tab: per task, wall-clock minutes from events.log and, where the
      usage data exists, Claude and Codex usage at dispatch and done.
- [ ] PROTOCOL.md says: a new rule names the measured loss it removes; a rule a script can
      enforce goes into `bin/squad`.
- [ ] `bash test/smoke.sh` and `shellcheck` pass.

## Plan
- `templates/roles/lead.md`, `templates/PROTOCOL.md`, `templates/LESSONS.md`.
- `bin/squad`: Cost tab in `cmd_report`; usage snapshot added to dispatch and done events.

## Tests
- smoke: Cost tab rows from a fixture events.log with known times.
- smoke: `squad init` copies LESSONS.md.

## Assumptions & open questions
1. Token counts per seat are only as exact as the usage data squad already reads
   (plan windows in %); exact tokens per task are not available. The tab says so.
