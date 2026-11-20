# 022 · The team pushes its integration branch; never main, never production
Status: Approved (the owner, 20 Nov 2026: the simpler version)
Size: S (≤ 2 h)

## Goal
The team commits, merges and pushes its own work (the owner, 20 Nov 2026: "allow push on squad … push
only for the current branch but not in main or production"). Today `squad git push` is refused and
squad's protocol says "never push", so the work stays on the owner's machine until the owner pushes by hand.

## Scope
- In: `squad git push`, with no arguments, pushes the branch it is on to `origin`, only when that branch
  is the team's integration branch (`team_base` in team.conf, default `team/integration`). The protocol
  and the lead's role file say so.
- Out: pushing any other branch (`main`, production, `task/*`); any argument (force, delete, tags,
  refspecs, another remote); pull requests and merges into `main` (they stay the owner's); a deploy.

## Done when
- [ ] `squad git push` on the integration branch pushes it to `origin`.
- [ ] It is refused, with the reason, on any other branch (`main`, a `task/*` branch) and with any argument
      (`--force`, a refspec, another remote); the remote stays unchanged.
- [ ] PROTOCOL.md and the lead's role file say: the lead pushes the integration branch after each merged
      candidate; nothing else is pushed; `main` and production stay the owner's.
- [ ] Smoke passes on `/bin/bash` 3.2 and in CI; shellcheck is clean.

## Plan
- bin/squad `cmd_git`: a `push` case: no arguments, current branch must be `$TEAM_BASE`; runs
  `git push origin $TEAM_BASE`.
- templates/PROTOCOL.md (the git line and rule 7), templates/roles/lead.md (the push lines), README.
- test/smoke.sh: a bare `origin` repository; one allowed push and the refusals.

## Tests
- Smoke: the allowed push lands in the bare remote; each refused case leaves the remote unchanged.

## Assumptions & open questions
- A push does not wait for the owner's visual review: the owner tests the merged result on screen, and
  `main` and production stay closed.
- No seat check: only the lead works on the integration branch; other seats are on `task/*` branches.
- Running teams get the new protocol and role file at their next `squad up` (hive: the lead is told with
  `squad notify`).
