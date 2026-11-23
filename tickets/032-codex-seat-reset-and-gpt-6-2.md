# 032 · A Codex seat takes every dispatch with no menu
Status: Approved (V!, 23 Nov 2026: "ok all, proceed")
Size: S (≤ 2 h)

## Goal
Every dispatch to the reviewer fails on hive, and the lead reviews in its place or presses a
key by hand (V!, 23 Nov 2026: "we need the fix with the review asap"). After this ticket a
Codex seat takes each task without a menu and without a person.

V! also asked for gpt-6.2-sol on the GPT seats (23 Nov 2026). That part is NOT in this ticket:
the real trial showed that Codex CLI 0.161.0 rejects the model at the first request (see
"Assumptions & open questions").

Cause (measured on Codex 0.161.0, 23 Nov 2026, in a throwaway session outside hive):
- Squad resets a Codex seat with `/new` before each task (`clear_cmd`, `bin/squad` line 263).
- `/new` in a git checkout shows the menu "Where should the new conversation run?
  1. Current checkout 2. New worktree". Squad types nothing into a menu, waits 65 s and logs
  `DISPATCH_FAILED not at its prompt`.
- `/clear` in the same session gives a new conversation and the empty prompt, with no menu.
- `/new` in a session started with `--disable worktrees` shows no menu.
- Hive: 9 of 9 reviewer dispatches failed since 22 Nov 02:34; the lead reviewed 3 of the 5
  tasks merged after PR #28. Hive's `team.conf` has `--disable worktrees` since 22 Nov, but
  the running reviewer started on 20 Nov, without it.

## Scope
- In: `clear_cmd` for the kind `codex`; README (the lowest tested Codex version); the smoke
  test of the reset command; one real trial with a Codex seat.
- Out (not in this ticket): the model name of the GPT seats; the kind `opencode` (it keeps `/new`: not measured); an answer
  typed by squad into any menu; the review rules; hive's files (see "Hive", below).

## Done when
- [ ] Squad resets a Codex seat with `/clear`; an opencode seat keeps `/new`.
- [ ] Real trial on `/Users/v/v-dev/squad-trial` with a Codex seat started without
      `--disable worktrees`: two dispatches in a row are delivered, each logs `DISPATCH`,
      none logs `DISPATCH_FAILED`, and the second starts with an empty conversation.
- [ ] `test/smoke.sh` passes in CI, with a test for the Codex reset command that fails before
      the change.

## Plan
- `clear_cmd`: `codex) echo "/clear"`, `opencode) echo "/new"`.
- Smoke test: the roster line of a Codex seat shows `/clear` (next to the opencode test,
  `test/smoke.sh` line 288).
- Real trial on the throwaway team, then the two reviewers, the verifier and the PR.

## Tests
- Smoke: Codex reset command (new); opencode reset command (existing, unchanged).
- Real trial: the second "Done when" item.

## Hive (the live team; a separate step, only on V!'s word)
Restart `rev-gpt` and `plan-gpt`, so `--disable worktrees` (in hive's `team.conf` since
22 Nov) acts. Side effect: each of the two seats loses its open conversation (the reviewer
starts each task with an empty one already). Hive runs `/Users/v/v-dev/squad`, so the merge
of this ticket plus a pull installs the `/clear` fix there; after that the restart is not
needed for the menu.

## Assumptions & open questions
- `/clear` is measured on Codex 0.161.0 only; README names 0.161 as the lowest tested version.
- gpt-6.2-sol, measured 23 Nov 2026: Codex CLI 0.161.0 (installed) answers a request for it
  with "The 'gpt-6.2-sol' model is not supported when using Codex with a ChatGPT account";
  gpt-6.1-sol answers. The model is in the model list of the Codex desktop app (client
  0.169.0) and not in the list of the CLI 0.161.0. Homebrew offers CLI 0.169.0. Assumed, not
  measured: the CLI 0.169.0 accepts the model with this account.
- Open decision for V!: upgrade the Codex CLI to 0.169.0 (it is the program of hive's GPT
  seats and of `dual-review`), then test gpt-6.2-sol and the `/clear` reset on it, then change
  the model in a new ticket. Recommendation: yes, while hive is idle, with the trial team
  first.
- Seen in the trial, not in this ticket: at a seat's first start in a new folder Codex asks
  "Trust this folder?", and `squad up` reports the seat as started.
