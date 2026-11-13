# 008 · Heavy runs from a snapshot, in their own process group, a sample mode for devs, and team.conf kept up to date
Status: Approved (V!, 13 Nov 2026)
Size: M

## Goal
A heavy run tests exactly one commit and nothing else, can always be stopped completely, and a
dev's run is short by design. Every team's `team.conf` gets the settings and seats a new squad
version needs, without anyone editing it by hand. Sources: docs/research/2026-11-13-software-factories.md
(rows 1, 2, 7: agent-engineering, Anthropic C compiler, Bazel test encyclopedia).

## Scope
- In: snapshot worktrees for dev runs; one process group per run; `--sample` with `{shard}`;
  `sample_percent`; `squad update-conf` and its automatic run in `squad up` and `squad init`;
  `upgrade off`; the containers reminder in docs/ROADMAP.md; role, protocol and README text.
- Out: containers or a second machine (reminder only); test-runner plugins (the sample mode
  uses the runner's own shard flag).

## Done when
- [x] A dev's `squad heavy` runs in `<repo>-team/<seat>-run`, a detached worktree at the commit it
      recorded, in the same subfolder the dev called it from; the dev's own worktree can change
      during the run; the setup command runs there again only when a lockfile changed.
- [x] Each heavy run is its own process group: a stop or a time-out ends every process in it
      (TERM, then KILL); a stale lock's leftover group is ended before the lock is freed; a
      stopped run never exits 0.
- [x] `squad heavy <seat> <task> --sample -- <cmd with {shard}>` replaces `{shard}` with `k/n`
      (n = 100 / `sample_percent`, k fixed per seat and task) and refuses a command without
      `{shard}`; `HEAVY_START` names the sample.
- [x] `squad update-conf` adds each setting and each seat role the team's preset has and
      `team.conf` lacks, says what it added, and changes nothing in a file that has them all;
      `squad up` and `squad init` run it; `upgrade off` in team.conf turns it off.
- [x] docs/ROADMAP.md holds the containers reminder with its sources; `bash test/smoke.sh` and
      `shellcheck` pass under bash 5 and 3.2.

## Plan
- `bin/squad`: `prepare_snapshot`, `run_in_group` (perl `setpgrp`, fallback: no group), group
  kill in `stop_tree` and `heavy_clear_stale` (`heavy/lock.pgid`), `--sample` parsing,
  `SAMPLE_PERCENT`; `cmd_update_conf` (preset recorded at init as `# preset: <name>`).
- `templates/PROTOCOL.md`, `templates/roles/dev.md`, `templates/TASK.md`, presets, README,
  docs/ROADMAP.md.

## Tests
- smoke: the run happens in `dev-a-run` at the recorded sha while the worktree moves on; a
  background child of the command is gone after a time-out; a dead owner's group is ended;
  `{shard}` replaced and the same for the same seat and task; refusal without `{shard}`;
  update-conf on an old 5-seat file adds the keys, `rev-gpt` reviewing the existing devs and
  `observer`, a second run adds nothing, `upgrade off` adds nothing, the `small` preset adds no seat.

## Assumptions & open questions
1. Snapshots are for dev seats; the tester already tests detached commits in its own worktree.
2. Paths in a dev's command are relative: an absolute path into the live worktree would bypass
   the snapshot (the protocol says so).
3. macOS has no `setsid`; perl (shipped with macOS) makes the group. Without perl the run works
   as before (process-tree stop).

## Evidence (13 Nov 2026)
`bash test/smoke.sh`: 270+ passed under bash 5 and /bin/bash 3.2.57; `shellcheck -S warning`: clean.
Smoke: 'a dev's run happens in its snapshot, at the commit it recorded', 'the dev's worktree can change
while its run reads the snapshot', 'the setup does not run again while no lockfile changed', 'a changed
lockfile runs the setup again', 'the run starts in the same subfolder of the snapshot', 'a timed-out run
ends every process of its group', 'a stopped run never passes, even when it exits 0 on the signal', 'a
dead owner's leftover run is ended before the lock is free', '--sample puts one fixed shard of ten in the
command', '--sample without {shard} is refused', 'update-conf adds what an old team.conf lacks', 'it adds
the GPT reviewer for the team's own devs, and the observer', 'a second run adds nothing', 'upgrade off
leaves team.conf alone', 'a small team gets the settings but no reviewer or observer', 'init from an old
personal default brings it up to date', 'the roadmap keeps the containers reminder'.
Also (found while planning the hive switch): a task already under way goes on without a contract.
