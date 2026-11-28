# 036 · A seat that exits with "Move to background" is resumed in its own conversation
Status: Done — awaiting PR review
Size: S (≤ 2 h)

## Goal
On 23 Nov 2026 the lead and the tester exited with Claude Code's "Move to background and
exit" (to keep the Storybook server alive). That option recorded a new, empty session in
`.team/seats/<seat>.session`, `squad up` failed to resume it and started both seats fresh;
the fresh lead began "continue Phase 3" while the team was stopped by the owner. After this
ticket a seat always comes back in its real conversation, or squad stops and says why.

## Scope
- In: the session record of a Claude seat (`.session`, the SessionStart hook); the resume in
  `squad up`; the fresh-start fallback; smoke tests; README "Resume".
- Out (not in this ticket): how Codex seats record their session; how the owner exits a seat.
- Decided (val3ntin-ch, 28 Nov 2026): a refused resume leaves a Codex seat stopped too, as
  every seat: one rule for all, no fresh start in place of a refused resume.

## Done when
- [x] A session file that holds an empty conversation (no user message) does not replace the
      last real one: squad keeps the last session that has at least one turn.
      Evidence: smoke "036: an empty recorded session is passed over", "the seat resumes the
      conversation it used last"; the replay of the real trial below.
- [x] When a resume fails, squad does not start a seat fresh with a "continue" line: it
      logs `RESUME_FAILED`, tells the owner, and leaves the seat stopped until `squad up
      --fresh <seat>` or a fixed session file.
      Evidence: smoke "036: a refused resume leaves the seat stopped", "and logs RESUME_FAILED
      and tells the owner", "up --fresh <seat> starts only that seat fresh", "a resume that stops
      on a dialog gets the dialog's hint".
- [x] Real trial on the throwaway team: a seat with a background shell exits with "Move to
      background"; `squad up` resumes its real conversation (same id, `--resume` in the
      process).
      Evidence (27 Nov 2026, Claude Code 2.1.323, a throwaway folder, not hive): session cf9bfd6a
      ran `sleep 900` in the background; a double Ctrl+D showed "Background work is running" and
      "Move to background and exit" was chosen. Its SessionStart hook then reported a new session
      15781e88 with `"source":"fork"` and a 228-byte transcript with no user turn; cf9bfd6a kept
      its 2 user turns. Those hook inputs, fed to this branch's `squad session-id`, give `.session`
      = 15781e88 and `seat_resume_id` = cf9bfd6a; main's code gives 15781e88 (the empty one that
      Claude Code refuses, as on 23 Nov). `claude --resume cf9bfd6a` then opened the conversation
      with its turns; its hook reported `"source":"resume"` with the same id. The source is
      `fork`, not `clear`, so this exit sets no floor.
      On hive, 23 Nov: the empty sessions 0a181170 (lead, 252 bytes) and 0c70238a (tester, 218
      bytes) hold only an ai-title and an agent-name line, no user turn.
- [x] `test/smoke.sh` passes in CI, with a test for each item that fails before the change.
      Evidence: PR #31, run 46118352050 on 8ce471c: ubuntu-latest and macos-latest pass.

## Plan
- The SessionStart hook writes a new id only when the transcript has a user turn, or keeps a
  short history and `squad up` picks the newest non-empty one.
- `start_seat`: a failed resume of the lead or of any seat with an open task stops instead of
  starting fresh.

## Tests
Smoke tests with a stand-in session folder; one real trial (item 3).

## Assumptions & open questions
- Measured on 23 Nov: the empty sessions were 252 and 218 bytes; the real ones 169 MB and
  0.75 MB. Assumed: "Move to background" starts a new session id in Claude Code 2.1.323.

## Verification
Independent verifier on 8ce471c (28 Nov 2026): READY; the live Claude Code run of item 3 is
for val3ntin-ch to confirm.

| Item | Result |
|---|---|
| In: session record, resume in `squad up`, no fresh fallback, smoke tests, README | PASS |
| Decided 28 Nov: a refused resume leaves a Codex seat stopped too | PASS |
| Out: how Codex seats record their session; how the owner exits a seat | PASS |
| "Done when" has 2–6 testable items | PASS |
| 1: an empty session does not replace the last real one | PASS |
| 2: a failed resume logs RESUME_FAILED, tells the owner, the seat stays stopped | PASS |
| 3: real trial: code path replayed with the trial's hook inputs | PASS |
| 3: real trial: the live Claude Code run | needs val3ntin-ch |
| 4: CI on HEAD | PASS |
| Review threads (7 of 7 resolved) | PASS |
| No secrets, no personal data | PASS |
