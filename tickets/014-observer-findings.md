# 014 · The observer's open findings (S-8, S-17, S-24, S-31, S-41, S-44, S-45, S-48, S-49, S-50)
Status: Approved (the owner, 17 Nov 2026: "fix all")
Size: M

## Goal
Remove the losses the observer measured in project A: hours of stall nobody saw, a lead stopped by a
usage limit, healthy runs killed as hung, approved tasks held, candidate commands split by dev runs.

## Done when
- [x] S-48: the team strip's watchdog writes STALLED and notifies the owner and the lead once when no event
      came for `stall_alert_minutes` (30) while a verdict, DONE or test result waits; it writes LIMIT and
      notifies the owner when a seat shows its usage limit; with `limit_fallback <model>` a Claude seat switches
      to it; it warns once a day when Claude's week passes 80 %.
- [x] S-17, S-41: the hung check counts the CPU of every process the run started (its group and every
      descendant, also in its own group), so a quiet suite that computes is not stopped.
- [x] S-44, S-31: `squad heavy --batch <file>` runs a candidate's commands under one lock (each with its
      own HEAVY_START/END and exit code); `--limit <minutes>` gives a tester's step its own limit.
- [x] S-24: `squad timed <seconds> -- <command>` stops a viewer or screenshot script; the dev role uses it.
- [x] S-49: one deep observer pass per loss (the loss is known by its start time).
- [x] S-50, S-8, S-45: role rules: an approved task is not held for one in review; candidate before a
      stop; the tester writes only the candidate report.
- [x] Smoke tests for each code item; shellcheck clean.
