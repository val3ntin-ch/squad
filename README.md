# squad

Give one strong agent a large task. It writes the spec, splits the work into small tasks, hands them to a team of developer agents, reviews every task itself, sends corrections until each one is right, and merges. You see the work once, at the end, when everything is green.

squad runs inside [herdr](https://herdr.dev). It is one bash script. It does not run agents itself: herdr hosts the real Claude Code sessions, and squad sets up the worktrees, panes, roles and rules that make them work as a team.

```bash
cd my-app
squad init                    # adds a team to this repository
$EDITOR .team/GOAL.md         # what you want built, in a few lines
herdr                         # then, in the herdr pane:
squad up                      # start the team
```

## The team

| Seat | Model | Job |
|---|---|---|
| `lead` | Claude Fable 5.2 | Writes the spec and the task briefs, decides, reviews every task, merges. Never implements. |
| `dev-a`, `dev-b`, `dev-c` | Claude Opus 5.5, medium effort | Implement one task each, in parallel, each in its own worktree. |
| `tester` | Claude Sonnet 5.5, low effort | Runs the checks, measures, saves screenshots. Evidence only. |

The strongest model sits where one mistake costs the most: the plan and the review. The cheapest model does what needs no judgement.

## Install

Requirements: `git`, `jq`, [herdr](https://herdr.dev) and Claude Code (`claude`), signed in once by hand.

```bash
git clone https://github.com/val3ntin-ch/squad ~/.squad
~/.squad/install.sh           # links ~/.local/bin/squad
squad doctor                  # checks what is installed
squad permissions             # once per machine: Claude usage status line
```

## Make it your default

```bash
squad config                  # writes ~/.config/squad/team.conf
```

That file is your personal team. Edit it once (seats, models, effort) and every `squad init` and `squad new` starts from it. A project can still change its own copy in `.team/team.conf`.

## Commands

| Command | What it does |
|---|---|
| `squad new <dir>` | Creates a project folder with git, a first commit and a team. |
| `squad init` | Adds a team to the repository you are in. Fills the `setup` line from the lockfile it finds (pnpm, yarn, npm, bun, uv, poetry, bundler) so every worktree gets its dependencies. |
| `squad up` | Creates the worktrees, opens a herdr workspace and starts every agent. Run it from a pane inside herdr. Safe to run again: it keeps running seats and starts only what is missing. |
| `squad brief` | Starts the lead again with one short line. After a restart the lead resumes from the files. |
| `squad watch` | The live board in the team tab. `squad up` starts it; `--once` prints it once. |
| `squad usage` | One line of plan usage: the 5-hour and 7-day windows, and when a nearly used-up window comes back. |
| `squad status` | Shows the seats, the spec status, the task table and the agent states. |
| `squad down` | Stops the team: closes its herdr workspace and every agent in it. Worktrees, branches and `.team/` stay. |
| `squad clean` | Removes the team's worktrees. Worktrees with uncommitted work are kept, and branches are never deleted. |
| `squad config` | Creates or shows your personal default team. |
| `squad presets` | Lists the built-in teams. |
| `squad doctor` | Checks what is installed. |
| `squad permissions` | Once per machine: sets Claude Code's status line to `squad statusline`, unless you already have one. |
| `squad git`, `squad herdr`, `squad done` | Used by the agents. You do not need them. |

`init`, `new` and `config` accept `--preset NAME`.

**Several projects at once:** herdr agent names are unique per herdr session, so two teams cannot share one session (both have a `lead`). Give each project its own: `cd my-app && herdr --session my-app`, then `squad up`.

## Defining a team

`.team/team.conf` has one line per seat:

```
seat <name> <agent> <role> <reviews> [agent arguments...]
```

```
seat lead    claude  lead    -  --model claude-fable-5-2
seat dev-a   claude  dev     -  --model claude-opus-5-5 --effort medium
seat dev-b   claude  dev     -  --model claude-opus-5-5 --effort medium
seat dev-c   claude  dev     -  --model claude-opus-5-5 --effort medium
seat tester  claude  tester  -  --model claude-sonnet-5-5 --effort low

base team/integration
rounds 5
setup pnpm install --frozen-lockfile
```

- **arguments** after the fourth column go to the agent's own CLI unchanged. That is how you choose the model and the effort.
- **role** is `lead`, `dev`, `tester` or `reviewer`. There is exactly one lead. A `reviewer` seat is optional: without one, the lead reviews.
- **base** is the branch finished tasks are merged into.
- **rounds** is how many review rounds a task may take before the lead brings it to you.
- **setup** runs once in every new worktree, so each agent can build and test.

Built-in presets:

| Preset | Seats |
|---|---|
| `default` | lead, three devs, tester |
| `small` | lead, one dev, tester; for a small feature |
| `large` | lead, five devs, tester; for a task with many independent parts |

## The board

`squad watch` runs at the bottom of the team tab and refreshes every 20 seconds:

```
 Claude 5h ▓▓░░░  41% 7d ▓░░░░  12%
 ▓▓▓▓▓▓▓▓░░░░░░░░░░░░ 2/5 merged · review 1 · dev 1 · todo 1
 ✔ T-001   ✔ T-002   ◆ T-003 review-2 dev-b   ● T-004 dev dev-a   ○ T-005
 lead ●  dev-a ●  dev-b ○  dev-c ○  tester ·    last: 10:12:03 dev-b T-003 DONE
```

Line by line: plan usage; progress of the whole goal; every task with its state and owner; every seat (● working, ○ idle, ! blocked, · off) and the last event. In a terminal the states have colours: green merged, magenta in review, blue in test, cyan in development, red blocked.

## Roles load at start

Each seat's identity, the protocol and its role are written to `.team/seats/<seat>.md` and loaded as a system prompt when the agent starts (`--append-system-prompt-file`). Nothing is typed into the panes, and the role survives the `/clear` the lead sends between tasks. The lead gets one line to start.

## Layout

`squad up` picks a layout from the terminal width (`SQUAD_LAYOUT=talk|mission|focus` forces one):

| Layout | When | Tabs |
|---|---|---|
| **talk** | default | `team`: lead (60%) beside the devs, live board below · `review`: tester · `changes`: lazygit |
| **mission** | ≥ 220 columns | `team`: lead, each dev, tester, board below · `changes` |
| **focus** | < 120 columns | `team`: lead + board · `devs` · `review` · `changes` |

Switch tabs with herdr's `prefix 1`…`9` (or `prefix n` / `prefix p`); `prefix z` zooms a pane. The `changes` tab runs lazygit on the integration worktree: every `task/*` branch, worktree and diff (only when lazygit is installed).

The usage bars come from Claude itself: it passes its plan limits to its status line, which `squad permissions` sets to `squad statusline` (the bar shows `—` until a Claude session has answered once).

## How the team works

They do not chat. Work travels through small files, and each message is one line.

```
you   ── GOAL.md ──▶ lead
lead  writes SPEC.md, tasks/T-001.md …, TASKS.md, and logs each decision in DECISIONS.md
lead  ── "Task T-001 is yours" ──▶ dev-a          (one line; the brief is the file)
dev-a builds, checks every acceptance row, writes reports/T-001-dev.md, runs: squad done
lead  ── "Test task T-001" ──▶ tester
tester runs the checks, measures, saves screenshots, writes reports/T-001-test.md
lead  reviews: the whole diff, every acceptance row, every screenshot
lead  ── "T-001 needs changes, read review-1" ──▶ dev-a      … until it is right
lead  merges, dispatches the next task
lead  ── READY.md ──▶ you                          (only when everything is green)
```

| File in `.team/` | Purpose |
|---|---|
| `GOAL.md` | What you want. The only thing you write. |
| `SPEC.md` | The design, the checks and the visual check. Written by the lead. |
| `DECISIONS.md` | Every decision the lead took without you, with its reason and source. |
| `TASKS.md` | The status table. Only the lead edits it. |
| `tasks/<ID>.md` | One complete brief per task: goal, files, acceptance table, check command, visual check, references. |
| `reports/` | One short report per step, each with the acceptance table and its evidence. Screenshots in `reports/<ID>-shots/`. |
| `READY.md` | The lead's final summary and the list of what to look at. |

**The lead decides.** It does not ask you how to do things. It looks in the repository first (rules, docs, the libraries already in use). When the repository does not answer, it searches the web in trusted sources: official documentation and guidelines, the library's own source and release notes, and the best maintained open-source projects that solve the same problem. For a library or a version it checks the current stable release, the maintenance, the licence and the performance cost. Each decision goes into `DECISIONS.md` with its reason and its source.

**Fresh facts only.** No seat acts on memory or on an old context. The files and git are the truth and are read again before each step; an API, a version or a flag is read where it is defined, never recalled; every task starts from a cleared context; the lead clears its own context when it gets long and resumes from the files.

**The review skips nothing.** The lead reads the whole diff, checks every acceptance row against evidence it saw itself, and looks at every screenshot. A finding names the place, the expected value and the actual value. The task goes back until every row is met.

**The tester goes first.** The lead spends its review only on work whose checks already pass.

No agent pushes. Your own checkout is never touched: all work happens in worktrees in `<repo>-team/`. `squad init` adds `.team/` to `.git/info/exclude`, so team files stay out of your commits.

## Your part

- **Write the goal** in `.team/GOAL.md`. Say where the rules, the design and the references are.
- **Answer permission prompts.** The lead tells you when a pane shows one; it never answers them for you. Allow git, your package manager and your test commands in Claude Code once, or agents will stall.
- **Review at the end.** Read `READY.md`, look at what it lists, read `DECISIONS.md`, then push the base branch.
- **Decide what the lead brings you:** a task that is not approved after the allowed rounds, or anything that needs a push, a deletion or a change outside the repository.

## Why this keeps token cost down

- One brief per task. A dev reads one small file, not the spec, the task list and the history.
- One line per message. Agents read files and diffs, never each other's transcripts.
- Evidence tables. The lead verifies a row instead of re-deriving what the dev did.
- The cheap seat collects the evidence; the expensive seat only judges it.
- Failing work never reaches the review.
- Tasks own named files, so devs never collide and nothing is redone after a merge.
- One heavy run at a time. Devs run only the checks of their own task; the tester alone runs the full suite, one task at a time. Parallel full runs on one machine make every run slower and turn slow tests into false failures.
- The lead reacts to events instead of polling, and clears each worker's context between tasks.

Idle agents cost nothing. For a one-file change, use one agent; a team pays off on work that splits into several independent tasks.

## First run of a project

Claude asks once whether to trust a new repository. `squad up` starts one seat, holds the others while the dialog is open, and names the pane. Answer it, then run `squad up` again; it starts the rest. After that the project starts with no dialogs: squad gives every seat write access to `.team/` and the repository's `.git`, and gives the lead read access to the devs' worktrees for its review.

## Troubleshooting

| Symptom | What to do |
|---|---|
| "run this from a pane inside herdr" | Start `herdr` in the repository and run `squad up` there. |
| A seat "did not become ready" | herdr's error is printed above it. Usually the agent shows a first-run dialog (trust this folder, sign in): open its pane, answer it, then `squad up` again. |
| "an agent named … is already running" | A team is already up in this herdr session: use it, or run the other project's team in its own session, `herdr --session <project>`. |
| The lead seems stuck | Look in herdr's sidebar for a blocked agent and answer it. |
| An agent lost track | Tell it to read `.team/PROTOCOL.md` and its role file again. |
| A seat rejects `--effort` | Check the levels your Claude Code accepts with `claude --help`, and change the seat line. |

## Status of this project

Version 0.8.0. This version changes the team: one lead that plans, decides and reviews; Claude developers; a cheap tester; no second vendor. `test/smoke.sh` covers squad's own logic against a stand-in for herdr, including the shipped presets and the board.

Not yet run end to end with real agents in this shape. Version 0.7.0 ran end to end on herdr 0.9.3 with its earlier team.

Known limits:

- Agent arguments cannot contain quoted spaces.
- Panes are stacked by repeated splitting, so with many seats the lower panes are small; resize them in herdr.
- The lead's review costs the most tokens on the team. Keep tasks small, so each review is small.

## Contributing

Run `bash test/smoke.sh` and `shellcheck bin/squad install.sh test/smoke.sh` before sending a change (CI runs both). The role prompts in `templates/roles/` matter as much as the script.

## License

MIT
