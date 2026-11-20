# 022 · The team pushes its integration branch; never main, never production
Status: Done — awaiting PR review
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

## Verification
Independent verifier, 20 Nov 2026 (branch squad-push): READY.

| Item | Result | Evidence |
|---|---|---|
| Push on the integration branch reaches origin | PASS | smoke: "squad git push pushes the integration branch", "origin has the integration branch, and only it" |
| Refused on other branches and with any argument; remote unchanged | PASS | 6 refusal rows (task branch, main, `--force`, refspec, custom base, base named main); "a refused push leaves the remote empty" |
| PROTOCOL.md and lead role say so | PASS | PROTOCOL.md lines 10 and 109; lead.md lines 142, 228, 252 |
| Smoke on bash 3.2 and 5, shellcheck | PASS locally (510/510 both); CI on the PR | `shellcheck -S warning` exits 0 |
| Out items (no other branch, no arguments, no PR/merge/deploy code) | PASS | diff touches README, bin/squad, PROTOCOL, lead.md, smoke, ticket |
| No secrets, no personal data | PASS | scan of the diff |

Note: the README also gains a short planner section (the owner asked how to use the planner, 20 Nov).
