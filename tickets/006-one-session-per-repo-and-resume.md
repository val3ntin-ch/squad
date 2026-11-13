# 006 · One herdr session per repository, and resume where the team stopped
Status: Approved (V!, 13 Nov 2026)
Size: M

## Goal
`squad up` in a repository always lands in that repository's own herdr session, and after a
restart (of herdr, of the Mac) every seat comes back with its own conversation, with no
`/resume`, no dialog and no typed briefing.

## Scope
- In: `squad up` from any terminal (inside or outside herdr); a herdr session named after
  the repository; per-seat session ids; resume of Claude and Codex seats; resume of the
  observer; the restart note to the lead.
- Out: moving a running team between machines; herdr's own session storage.

## Done when
- [x] `squad up` run outside herdr starts or attaches the session `<repo>` (changed from `squad-<repo>`: V!'s running team already uses the session `hive`; `session <name>` in team.conf overrides it) and starts
      the team in it; run inside herdr in another repository's session, it stops and prints
      the one command to switch (`squad up` never mixes two repositories in one session).
- [ ] Two repositories can run teams at the same time, each in its own session, with no
      "an agent named lead is already running" error.
- [x] On first start squad gives each Claude seat `--session-id <uuid>` and records it in
      `.team/seats/<seat>.session`; for Codex seats it records the session id after start.
- [x] After a restart, `squad up` starts each seat with `claude --resume <id>` or
      `codex resume <id>` (same model and arguments), and sends the lead and the observer one
      line: "squad restarted at <time>: check heavy lock, queue and uncommitted work".
      A seat whose session cannot be resumed starts fresh and says so in events.log.
- [ ] A worker seat that was cleared for a new task gets a new session id at its next
      dispatch (so resume never brings back an old task).
- [x] `bash test/smoke.sh` and `shellcheck` pass.

## Plan
- `bin/squad` `cmd_up`: detect `$HERDR_*` env; outside herdr use `herdr --session squad-<repo>`
  (create the workspace and run `squad up` in its first pane through the API, then
  `herdr session attach`). Write the session name into `.team/herdr.session`.
- `start_seat`: add `--session-id` / `--resume`; Codex via `codex resume <id>` as agent args.
- `cmd_dispatch` (001): new session id after `/clear`.
- `brief()`: the restart note, replacing today's long typed resume message where the
  conversation itself comes back.

## Tests
- smoke (herdr stand-in): outside-herdr path calls `--session squad-<repo>`; inside another
  session it refuses with the switch command.
- smoke: first start passes `--session-id`; second start passes `--resume` with the same id;
  a missing session file gives a fresh start and an events.log line.

## Assumptions & open questions
1. To verify first (not verified yet): that herdr's API can create a workspace and run a
   command in a session from outside it, and that `herdr agent start --kind codex -- resume
   <id>` is accepted. If not, `squad up` outside herdr prints the two commands instead.
2. Assumption: `/clear` in Claude starts a new session id, so the resume id must be updated
   at each dispatch (checked at implementation time).
3. **Open decision for V!:** the observer's model. Your hive observer runs Opus 5.5 and its
   analysis was good; the ticket planned Sonnet (cheaper). Recommended: Sonnet for the
   watch passes, and Opus only when a pass finds a loss over 30 min.

## Evidence (13 Nov 2026)
`bash test/smoke.sh`: 234 passed under bash 5 and under /bin/bash 3.2.57; `shellcheck -S warning`: clean. smoke: 'outside herdr, up brings the team up in the repository's own session', 'outside herdr, up then attaches the session', 'inside another repository's session, up refuses and names the session', 'a Claude seat records its session id from its SessionStart hook', 'the watcher records each running seat's conversation from herdr', 'after a restart a Claude seat resumes its own conversation', 'the Codex reviewer resumes its own recorded session', 'a refused resume falls back to a fresh start once', 'up --fresh starts new conversations'. Open (needs a real run): two repositories at once on real herdr; a new session id after a real `/clear` (the SessionStart hook fires on clear in Claude Code; not run here). Not verified on real herdr: starting a session from outside herdr.
