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
git clone <this repository> ~/.squad
~/.squad/install.sh           # links ~/.local/bin/squad
squad doctor                  # checks what is installed
```

## Make it your default

```bash
squad config                  # writes ~/.config/squad/team.conf
```

That file is your personal team. Edit it once (seats, agents, models) and every `squad init` and `squad new` starts from it. A project can still change its own copy in `.team/team.conf`.

## Commands

| Command | What it does |
|---|---|
| `squad new <dir>` | Creates a project folder with git, a first commit and a team. |
| `squad init` | Adds a team to the repository you are in. |
| `squad up` | Creates the worktrees, opens a herdr workspace, starts and briefs every agent. Run it from a pane inside herdr. |
| `squad brief` | Sends the role briefing again, after you fixed a blocked agent or restarted herdr. |
| `squad status` | Shows the seats, the spec status, the task table and agent states. |
| `squad clean` | Removes the team's worktrees. Worktrees with uncommitted work are kept, and branches are never deleted. |
| `squad config` | Creates or shows your personal default team. |
| `squad presets` | Lists the built-in teams. |
| `squad doctor` | Checks requirements. |

`init`, `new` and `config` accept `--preset NAME`.

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

## How the team works

They do not chat. The lead is the only agent that sends messages, one short line per task through herdr, and then blocks until that agent is idle:

```
lead ── herdr agent prompt dev-a "Task T-001 is yours…" ──▶ dev-a
lead ── herdr agent wait dev-a ──▶ (blocks, costs nothing)
dev-a writes .team/reports/T-001-dev.md and stops
```

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
| A seat "did not become ready" | Open its pane, answer the dialog (trust this folder, sign in), then `squad brief`. |
| "an agent named … is already running" | A team is up. Use it, or close its workspace first. |
| The lead seems stuck | Look in herdr's sidebar for a blocked agent and answer it. |
| An agent lost track | Tell it to re-read `$TEAM_DIR/PROTOCOL.md` and its role file. |

## Status of this project

Version 0.1.0. `test/smoke.sh` runs squad against a stand-in for herdr and checks the commands it sends, the worktrees it creates and its error handling; all checks pass. It has not yet been run against a real herdr server with real agents, so expect small adjustments on first use. herdr commands follow its 0.9.3 documentation.

Known limits:

- Agent arguments cannot contain quoted spaces.
- Panes are stacked by repeated splitting, so with many seats the lower panes are small; resize them in herdr.
- Sending `/clear` or `/new` to an agent through herdr is how the lead resets a worker's context; this is the least proven part.

## Contributing

Run `bash test/smoke.sh` before sending a change. The role prompts in `templates/roles/` matter as much as the script: improvements to how the agents hand work to each other are welcome.

## License

MIT
