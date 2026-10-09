# squad

Run a team of coding agents on your repository, inside [herdr](https://herdr.dev). One agent leads and designs, others implement, each dev is reviewed by a different vendor's model, and a tester runs the checks. You approve the spec and push the result.

squad is one bash script. It does not run agents itself: herdr hosts the real Claude Code, Codex and OpenCode sessions, and squad sets up the worktrees, panes, roles and rules that make them work as a team.

```bash
squad new my-app      # new project with git and a team
cd my-app && herdr
squad up              # in the herdr pane: start the team
```

## Install

Requirements: `git`, `jq`, [herdr](https://herdr.dev), and the agent CLIs your team uses (`claude`, `codex`, `opencode`), each signed in once by hand.

```bash
git clone https://github.com/val3ntin-ch/squad ~/.squad
~/.squad/install.sh           # links ~/.local/bin/squad
squad doctor                  # checks what is installed
squad permissions             # once: lets Codex seats run 'squad herdr' / 'squad git' without asking
```

If Codex is on your team, also set `check_for_update_on_startup = false` in
`~/.codex/config.toml` (update it with your package manager instead):
otherwise its "Update available" dialog stops seats on start.

## Make it your default

```bash
squad config                  # writes ~/.config/squad/team.conf
```

That file is your personal team. Edit it once (seats, agents, models) and every `squad init` and `squad new` starts from it. A project can still change its own copy in `.team/team.conf`.

## Commands

| Command | What it does |
|---|---|
| `squad new <dir>` | Creates a project folder with git, a first commit and a team. |
| `squad init` | Adds a team to the repository you are in. Fills the `setup` line from the lockfile it finds (pnpm, yarn, npm, bun, uv, poetry, bundler) so every worktree gets its dependencies. |
| `squad up` | Creates the worktrees, opens a herdr workspace, starts and briefs every agent. Run it from a pane inside herdr. Safe to run again: it keeps running seats, adopts agents you started by hand in a seat's pane, starts only what is missing and briefs only seats that were never briefed. |
| `squad brief` | Sends the role briefing again, after you fixed a blocked agent or restarted herdr. |
| `squad watch` | The live strip in the team tab: plan usage bars per vendor, each task's owner and state, each seat's state, the last event. `squad up` starts it; `--once` prints it once. |
| `squad usage` | One line of plan usage: Claude and Codex, 5-hour and 7-day windows, and when a nearly used-up window comes back. |
| `squad statusline` | Use as Claude Code's status line (`"statusLine": {"type": "command", "command": "squad statusline"}`): shows the model and usage bars, and records Claude's usage for `squad watch`. |
| `squad status` | Shows the seats, the spec status, the task table and agent states. |
| `squad down` | Stops the team: closes its herdr workspace and every agent in it. Worktrees, branches and `.team/` stay; `squad up` starts it again. |
| `squad clean` | Removes the team's worktrees. Worktrees with uncommitted work are kept, and branches are never deleted. |
| `squad config` | Creates or shows your personal default team. |
| `squad presets` | Lists the built-in teams. |
| `squad doctor` | Checks requirements, the Codex rule and Codex's update dialog. |
| `squad permissions` | Adds two Codex rules so `squad herdr` and `squad git` never ask (every project). |
| `squad git <args>` | The git writes agents need (switch, add, commit, merge, rebase, restore, stash, branch) — never push, force or delete, and only inside a squad team. Agents use it; you don't need to. |
| `squad herdr <args>` | herdr bound to this team's session. Agents use it; you don't need to. |

`init`, `new` and `config` accept `--preset NAME`.

**Several projects at once:** herdr agent names are unique per herdr session, so
two teams can't share one session (both have a `lead`). Give each project its
own session: `cd my-app && herdr --session my-app`, then `squad up`.

## Defining a team

`.team/team.conf` has one line per seat:

```
seat <name> <agent> <role> <reviews> [agent arguments...]
```

```
seat lead        codex     lead      -            -m gpt-6.1-sol
seat dev-a       claude    dev       -            --model claude-opus-5-5
seat dev-b       codex     dev       -            -m gpt-6.1-sol
seat dev-c       opencode  dev       -
seat rev-sol     codex     reviewer  dev-a        -m gpt-6.1-sol
seat rev-claude  claude    reviewer  dev-b,dev-c  --model claude-opus-5-5
seat tester      claude    tester    -            --model claude-sonnet-5-5

base team/integration
setup yarn install --immutable
```

- **agent** is any agent herdr can start: `claude`, `codex`, `opencode`, `gemini`, `cursor` and others. Arguments after the fourth column go to that agent's own CLI unchanged, which is how you choose the model.
- **role** is `lead`, `dev`, `reviewer` or `tester`. There is exactly one lead. Reviewers and the tester are optional.
- **reviews** names the dev or devs a reviewer checks. Pair each dev with a reviewer from a different vendor; a model is worst at spotting the mistakes it would make itself.
- **base** is the branch finished tasks are merged into.
- **setup** runs once in every new worktree, so each agent can build and test. Each agent has its own checkout, and a checkout without installed dependencies cannot run tests.

Built-in presets:

| Preset | Seats |
|---|---|
| `default` | Sol lead, Claude Opus dev, Sol dev, cross-vendor reviewers, Claude Sonnet tester |
| `opencode` | the default team plus an OpenCode dev |
| `small` | Sol lead, Claude Opus dev, Sol reviewer; for small features |

An OpenCode seat starts with the model your own OpenCode configuration selects. Add arguments to its line to pin one.

## Layout

`squad up` picks a layout from the terminal width (`SQUAD_LAYOUT=talk|mission|focus` forces one):

| Layout | When | Tabs |
|---|---|---|
| **talk** | default | `team`: lead (60%) beside the devs, live strip below · `review`: reviewers + tester · `changes`: lazygit |
| **mission** | ≥ 220 columns | `team`: lead, each dev, reviewers + tester stacked, strip below · `changes` |
| **focus** | < 120 columns | `team`: lead + strip · `devs` · `review` · `changes` |

Switch tabs with herdr's `prefix 1`…`9` (or `prefix n` / `prefix p`); `prefix z` zooms a pane. The `changes` tab runs lazygit on the integration worktree: every `task/*` branch, worktree and diff (only when lazygit is installed).

Usage comes from the vendors themselves: Codex writes its rate limits into its session files; Claude passes them to its status line, so set `squad statusline` as Claude's status line to see the Claude bar (it shows `—` until a Claude session has answered once).

## How the team works

They do not chat. The lead hands out work with one short line per task, never blocks on any one agent, and reacts when a worker reports back. A worker ends every step with `squad done`, which sends the lead one line — herdr queues it if the lead is busy, so nothing finishing goes unnoticed:

```
lead  ── "Task T-001 is yours…" ──▶ dev-a      lead ── "Task T-002 is yours…" ──▶ dev-b
dev-a writes .team/reports/T-001-dev.md, runs: squad done dev-a T-001 DONE
lead  ◀── [squad] dev-a finished T-001: DONE — report: …   (queued if the lead is busy)
lead  ── "Review task T-001, round 1" ──▶ rev-sol
```

Every `squad done` is also appended to `.team/events.log`; the live strip shows the last one.

Everything else travels through files in `.team/`:

| File | Purpose |
|---|---|
| `SPEC.md` | What is being built. Written by the lead, approved by you. |
| `TASKS.md` | The task list and its status. Only the lead edits it. |
| `ROSTER.md` | Who is on the team. Generated from `team.conf`. |
| `reports/` | One short report per step: dev, review, test. |
| `PROTOCOL.md`, `roles/` | The rules and the role prompts. Refreshed by `squad init`. |

One task goes through the loop like this:

1. The **dev** branches `task/T-001` from the base branch in its own worktree, implements, runs the check, commits and writes a report.
2. The **reviewer** reads the diff and writes `APPROVE` or `CHANGES`. After two rounds without approval the lead brings it to you.
3. The **tester** checks out the branch, runs the checks and writes `PASS` or `FAIL` with exit codes.
4. The **lead** merges into the base branch and updates `TASKS.md`.

No agent pushes. When all tasks are merged you review the base branch and push it yourself.

`squad init` adds `.team/` to `.git/info/exclude`, so team files stay out of your commits. Your own checkout is never touched: all work happens in worktrees in `<repo>-team/`.

## First run of a project

Claude and Codex each ask once whether to trust a new repository (both save it
per repository). `squad up` starts one seat per agent, holds that agent's other
seats while its dialog is open, names the dialog and the pane — so a new
project means **two answers**: one in a Claude pane, one in a Codex pane. Then
run `squad up` again; it starts the rest. After that, the same project starts with no
dialogs, and a task runs from spec to merge without permission prompts:
squad gives Claude and Codex seats write access to `.team/` and the
repository's `.git` (`--add-dir`), runs Codex in `workspace-write`, and the
lead reaches herdr through `squad herdr`, which `squad permissions` allows.
Codex's sandbox keeps `.git` read-only by design, so Codex seats make their
git writes through `squad git`, the second rule `squad permissions` adds.

## Your part

- **Approve the spec.** The lead writes `SPEC.md` and stops. Nothing else happens until you approve it. This is the cheapest moment to change direction.
- **Answer blocked agents.** A blocked pane is a question or a permission prompt. The lead tells you about it but does not answer permission prompts for you.
- **Set permissions once.** Allow git, your package manager and your test commands in each agent CLI, or agents will stall on prompts.
- **Decide escalations**: a task that failed review twice, a check that cannot run, a spec that turned out wrong.

## Why this keeps token cost down

- One agent thinks before the whole team works: the spec gate.
- Tasks own named files, so devs never collide and nothing is redone after a merge.
- Agents read short reports and diffs, never each other's transcripts.
- Review stops after two rounds.
- The lead waits on herdr's agent state instead of polling, and clears each worker's context between tasks.
- Expensive models sit only where judgement matters.

Idle agents cost nothing. For a one-file change, use one agent; a team pays off on features that split into several independent tasks.

## Troubleshooting

| Symptom | What to do |
|---|---|
| "run this from a pane inside herdr" | Start `herdr` in the repository and run `squad up` there. |
| A seat "did not become ready" | herdr's error is printed above it. Usually the agent shows a first-run dialog (trust this folder, sign in): open its pane, answer it, then `squad brief`. A pane whose shell is still starting is retried for up to a minute automatically. |
| Codex: "Error adding directories … do not allow additional writable roots" | Fixed in 0.2.0 (squad passes `-s workspace-write`). If your seat line sets its own `-s read-only`, remove it. |
| The lead's herdr calls reach the wrong session | Agents must use the `squad herdr …` commands written in `.team/roles/`, not plain `herdr`: Codex runs commands through a daemon that can carry another pane's environment. |
| "an agent named … is already running" | A team is already up in this herdr session: use it (`squad brief`), or run the other project's team in its own session, `herdr --session <project>`. |
| The lead seems stuck | Look in herdr's sidebar for a blocked agent and answer it. |
| An agent lost track | Tell it to re-read `$TEAM_DIR/PROTOCOL.md` and its role file. |

## Status of this project

Version 0.6.0. Run end to end on herdr 0.9.3 with real agents, default 6-seat
team (GPT-6.1 Sol lead, dev and reviewer in Codex; Claude Opus dev and
reviewer; Claude Sonnet tester), on a three-task goal: spec and approval, both
devs in parallel, cross-vendor reviews (3 × `APPROVE`), a test run per task
plus a final integration run (`PASS`), three merges, context cleared between
tasks — with no permission prompt after the two first-run trust answers.
`test/smoke.sh` covers squad's own logic against a stand-in for herdr; CI runs
it with shellcheck on Linux and macOS, including macOS's bash 3.2.

Known limits:

- Agent arguments cannot contain quoted spaces.
- Panes are stacked by repeated splitting, so with many seats the lower panes are small; resize them in herdr.
- OpenCode seats get no `--add-dir` (it has no such flag): allow `.team/` in OpenCode's own permission config.

## Contributing

Run `bash test/smoke.sh` and `shellcheck bin/squad install.sh test/smoke.sh` before sending a change (CI runs both). The role prompts in `templates/roles/` matter as much as the script: improvements to how the agents hand work to each other are welcome.

## License

MIT
