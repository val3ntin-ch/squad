# squad

Give one strong agent a large task. It writes the spec, splits the work into small tasks, hands them to a team of developer agents, has every task tested and reviewed by another vendor's model, decides on every finding, and merges. An observer watches the team and writes down what goes wrong and what to change. You see the work once, at the end, when everything is green, and one report page shows every decision and why it was taken.

squad runs inside [herdr](https://herdr.dev). It is one bash script. It does not run agents itself: herdr hosts the real Claude Code and Codex sessions, and squad sets up the worktrees, panes, roles and rules that make them work as a team.

```bash
cd my-app
squad init                    # adds a team to this repository
$EDITOR .team/GOAL.md         # what you want built, in a few lines
squad up                      # from any terminal: opens this repository's herdr session and starts the team
```

## The team

| Seat | Model | Job |
|---|---|---|
| `lead` | Claude Fable 5.2 | Writes the spec and the task briefs, decides, adjudicates every review, merges. Never implements. |
| `dev-a`, `dev-b`, `dev-c` | Claude Opus 5.5, medium effort | Implement one task each, in parallel, each in its own worktree. From review round 4 a fix runs on Fable. |
| `tester` | Claude Sonnet 5.5, low effort | QA. Agrees each task's acceptance contract before code is written, then runs the checks, measures, saves screenshots. Evidence only. |
| `rev-gpt` | GPT Sol 6.1, medium effort (Codex) | Reviews every diff after the tester's PASS, with a fresh context and another vendor's eyes. |
| `observer` | Claude Sonnet 5.5, low effort | Watches the team, measures what goes wrong, and writes ranked suggestions. A pass that finds a loss over 30 minutes is redone on Opus. |

The strongest model sits where one mistake costs the most: the plan and the decisions. The cheapest models do what needs no judgement. The reviewer is another vendor on purpose: a model that did not write the brief or the code sees what the authors do not.

## Install

Requirements: `git`, `jq`, [herdr](https://herdr.dev), Claude Code (`claude`) and Codex (`codex`), each signed in once by hand.

```bash
git clone https://github.com/val3ntin-ch/squad ~/.squad
~/.squad/install.sh           # links ~/.local/bin/squad
squad doctor                  # checks what is installed
squad permissions             # once per machine: Claude usage status line, Codex rules for squad's commands
```

## Make it your default

```bash
squad config                  # writes ~/.config/squad/team.conf
```

That file is your personal team. Edit it once (seats, models, effort) and every `squad init` and `squad new` starts from it. A project can still change its own copy in `.team/team.conf`.

## One herdr session per repository

Each repository's team runs in its own herdr session, named after the repository (`session <name>` in team.conf changes it). Two projects never share a session, so two `lead` seats never collide.

- `squad up` from a terminal outside herdr starts or attaches that session and starts the team in it. Its start log is `.team/up.log`.
- `squad up` inside herdr works in that repository's session and refuses another repository's session, with the command to switch.
- **Resume.** After a restart (herdr, the Mac), `squad up` brings every seat back with its own conversation: Claude seats with `--resume <their session>`, Codex seats with `codex resume <their session>`. A Claude seat records its current session at every start, `/clear` and compaction (a SessionStart hook passed with `--settings`). The lead and the observer then get one line: check the heavy lock, the queue and uncommitted work. `squad up --fresh` starts new conversations instead.

## Commands

| Command | What it does |
|---|---|
| `squad new <dir>` | Creates a project folder with git, a first commit and a team. |
| `squad init` | Adds a team to the repository you are in. Fills the `setup` line from the lockfile it finds (pnpm, yarn, npm, bun, uv, poetry, bundler) so every worktree gets its dependencies. |
| `squad up [--fresh]` | Creates the worktrees, opens the repository's herdr session and workspace, and starts or resumes every agent. Safe to run again: it keeps running seats and starts only what is missing. |
| `squad report [--live\|--open]` | Writes `.team/report.html`: decisions, observer, timeline, QA, cost, events. `--live` is the report tab; `--open` opens the page. |
| `squad brief` | Starts the lead again with one short line. |
| `squad watch` | The live board in the team tab: usage, tasks, seats and their trouble. `--once` prints it once. |
| `squad usage` | One line of plan usage: the 5-hour and 7-day windows, and when a nearly used-up window comes back. |
| `squad status` | Shows the seats, the spec status, the task table and the agent states. |
| `squad down` | Stops the team: closes its herdr workspace and every agent in it. Worktrees, branches and `.team/` stay. |
| `squad clean` | Removes the team's worktrees. Worktrees with uncommitted work are kept, and branches are never deleted. |
| `squad config` | Creates or shows your personal default team. |
| `squad update-conf` | Adds the settings and seats a new squad version needs to `.team/team.conf` and says what it added. `squad up` and `squad init` run it; a file that has everything is left alone. |
| `squad presets` | Lists the built-in teams. |
| `squad doctor` | Checks what is installed. |
| `squad permissions` | Once per machine: Claude Code's status line, and the Codex rules for the squad commands its seats run. |

Used by the agents (you do not need them): `squad dispatch`, `squad done`, `squad heavy`, `squad merge`, `squad notify`, `squad consult`, `squad decisions`, `squad git`, `squad herdr`, `squad session-id`.

`init`, `new` and `config` accept `--preset NAME`.

## Defining a team

`.team/team.conf` has one line per seat:

```
seat <name> <agent> <role> <reviews> [agent arguments...]
```

```
seat lead      claude  lead      -                  --model claude-fable-5-2
seat dev-a     claude  dev       -                  --model claude-opus-5-5 --effort medium
seat dev-b     claude  dev       -                  --model claude-opus-5-5 --effort medium
seat dev-c     claude  dev       -                  --model claude-opus-5-5 --effort medium
seat tester    claude  tester    -                  --model claude-sonnet-5-5 --effort low
seat rev-gpt   codex   reviewer  dev-a,dev-b,dev-c  -m gpt-6.1-sol -c model_reasoning_effort=medium
seat observer  claude  observer  -                  --model claude-sonnet-5-5 --effort low

base team/integration
rounds 5
escalate_model claude-fable-5-2
observer_deep_model claude-opus-5-5
consult codex --search exec -m gpt-6.1-sol -c model_reasoning_effort=medium
heavy_timeout 20
heavy_timeout_dev 10
sample_percent 10
stall_minutes 15
observe_minutes 20
verify_hook off
setup pnpm install --frozen-lockfile
```

- **arguments** after the fourth column go to the agent's own CLI unchanged. That is how you choose the model and the effort.
- **role** is `lead`, `dev`, `tester`, `reviewer` or `observer`. There is exactly one lead. Without a `reviewer` seat the lead reviews; without an `observer` nobody watches.
- **base** is the branch finished tasks are merged into.
- **rounds** is how many review rounds a task may take before the lead brings it to you.
- **escalate_model** is the model a fix runs on from round 4 (`squad dispatch --escalate`).
- **observer_deep_model** is the model for an observer pass after a loss over 30 minutes.
- **consult** is the command for the lead's second opinion on a real issue.
- **heavy_timeout** is how many minutes one heavy run may hold the lock (one lock for the whole machine, in `~/.cache/squad/heavy`: teams of several repositories share it); **heavy_timeout_dev** is the shorter limit for a dev's run. A dev's run needs a clean worktree (`squad heavy` refuses uncommitted changes), runs in a snapshot of that commit (`<repo>-team/.runs/<seat>`) so the dev can keep working, and every run is its own process group, so a stop ends all of it.
- **sample_percent** is the share of the tests a dev's `squad heavy … --sample -- <runner> --shard={shard}` run takes: one fixed shard per seat and task (Anthropic's `--fast` idea).
- **upgrade off** keeps squad from adding new settings and seats to this file. Without it, `squad up` and `squad init` run `squad update-conf`: whatever the team's preset has and team.conf lacks is added at the end, with a note; nothing that is there is changed.
- **stall_minutes**: a seat with an open task that has not worked for this long is stalled.
- **observe_minutes** is the longest gap between two observer passes.
- **verify_hook off** writes `.agents-verify-off` into every team worktree, so a global Stop hook that runs the whole repository's verify at every turn end skips them. The tester's runs are the gate.
- **session** is the herdr session name (default: the repository's name).
- **setup** runs once in every new worktree, so each agent can build and test.

Built-in presets:

| Preset | Seats |
|---|---|
| `default` | lead, three devs, tester, GPT reviewer, observer |
| `small` | lead, one dev, tester; for a small feature (the lead reviews) |
| `large` | lead, five devs, tester, GPT reviewer, observer; for a task with many independent parts |

## Layout

`squad up` picks a layout from the terminal width (`SQUAD_LAYOUT=talk|mission|focus` forces one). Every layout ends with the same three tabs:

| Tab | What it shows |
|---|---|
| `team` | the lead and the devs (by layout), the live board below |
| `review` | the tester and the reviewer (talk layout; mission puts them in `team`, focus adds a `devs` tab) |
| `changes` | lazygit on the integration worktree (when lazygit is installed) |
| `observer` | the observer, with the watcher that starts its passes below |
| `report` | the report, live in the terminal: now, open suggestions, decisions open for you, tasks, last events. Press `o` to open the HTML page. |

Switch tabs with herdr's `prefix 1`…`9` (or `prefix n` / `prefix p`); `prefix z` zooms a pane.

## The board

`squad watch` runs at the bottom of the team tab and refreshes every 20 seconds:

```
 Claude 5h ▓▓░░░  41% 7d ▓░░░░  12%
 ▓▓▓▓▓▓▓▓░░░░░░░░░░░░ 2/5 merged · review 1 · dev 1 · todo 1
 ✔ T-001   ✔ T-002   ◆ T-003 review-2 dev-b   ● T-004 dev dev-a   ○ T-005
 lead ●  dev-a ●  dev-b ○ stalled  dev-c ○  tester ·    last: 2026-11-13 10:12:03 dev-b T-003 DONE
 lock: tester since 10:05: pnpm turbo run test
```

Every seat shows ● working, ○ idle, ! blocked or · off, and its trouble in red: `dead` (its agent is gone), `login` (a sign-in error), `blocked` (a prompt or a question), `stalled` (an open task and no work for `stall_minutes`). Each trouble is written to `events.log` and told to the lead once.

## How the team works

They do not chat. Work travels through small files, and each message is one line. squad's own commands do the steps that must never go wrong.

```
you    ── GOAL.md ──▶ lead
lead   writes SPEC.md, tasks/T-001.md …, TASKS.md
lead   squad dispatch tester T-001 --contract  ▶ tester agrees the acceptance table: reports/T-001-contract.md
lead   squad dispatch dev-a T-001              ▶ dev-a builds, runs its checks and the consumers, writes its report
dev-a  squad done dev-a T-001 DONE             (refused while a row is missing or failed, or the dev check fails)
lead   squad dispatch tester T-001             ▶ tester runs the checks through squad heavy, saves screenshots
lead   squad dispatch rev-gpt T-001            ▶ GPT reviews the diff with a fresh context
lead   adjudicates each finding, checks the screens, then squad merge T-001 — or sends it back
lead   a real issue: squad consult "<question>" ▶ GPT brainstorms from official sources; both views go into DECISIONS.md
observer  measures every pass, writes observer/NOW.md and SUGGESTIONS.md; the lead adopts or rejects each one
lead   converge, LESSONS.md, READY.md ──▶ you   (only when everything is green)
```

| File in `.team/` | Purpose |
|---|---|
| `GOAL.md` | What you want. The only thing you write. |
| `SPEC.md` | The design, the checks and the visual check. Written by the lead. |
| `DECISIONS.md` | Every decision, with the question, the options, Claude's and GPT's view, the sources, the reason and its status (provisional — open for you, or final). |
| `consult/<n>.md` | GPT's independent brainstorm on a real issue, with its sources. |
| `TASKS.md` | The status table. Only the lead edits it. |
| `tasks/<ID>.md` | One complete brief per task: goal, files, acceptance table, dev check, check command, consumers, what to do when a check outside breaks, red run for bugs, visual check, references. |
| `reports/` | The contract, the dev's, the tester's and the review reports, each with the acceptance table and its evidence. Screenshots in `reports/<ID>-shots/`. |
| `events.log` | One line per dispatch, report, heavy run, merge, decision, consult, trouble and restart, with date and time. |
| `observer/NOW.md`, `observer/SUGGESTIONS.md` | What is wrong now and what it costs; ranked changes with their evidence and status. |
| `LESSONS.md` | At the end: each finding that came back, and the cheapest change that stops it next time. |
| `READY.md` | The lead's final summary: what to look at, rows not verified, decisions open for you. |
| `report.html` | All of the above on one page (`squad report`). |

**Decisions are yours; the team does not wait.** The lead decides provisionally, from the repository first and then from official sources (the library's documentation for the installed version, standards bodies such as W3C, WCAG, WHATWG and OWASP, release notes, well-maintained projects). On a real issue (a finding that comes back, a task at round 3, sources that disagree, architecture, a dependency, accessibility, security or data) it writes its own options, asks GPT for an independent brainstorm, and compares. Every provisional decision is listed for you in `READY.md` and in the report's Decisions tab before anything is pushed.

**QA comes first.** The tester agrees the acceptance contract before code is written: exact commands, thresholds, and the states the brief forgot. Every row ends in one of five results: pass, fail, pending, unavailable, inconclusive. Only pass counts; everything else is listed for the lead and for you.

**Fresh eyes on every diff.** GPT reviews with a fresh context and looks for the whole class of a defect, not one place at a time. Re-reviews read only the fix. The lead decides on each finding and does the visual check.

**Fresh facts only.** No seat acts on memory or on an old context. The files and git are the truth and are read again before each step; an API, a version or a flag is read where it is defined, never recalled; every task starts from a cleared context.

No agent pushes. Your own checkout is never touched: all work happens in worktrees in `<repo>-team/`. `squad init` adds `.team/` to `.git/info/exclude`, so team files stay out of your commits.

## Your part

- **Write the goal** in `.team/GOAL.md`. Say where the rules, the design and the references are.
- **Answer permission prompts and sign-in errors.** squad shows them in red on the board and tells the lead; the lead tells you. Allow git, your package manager and your test commands in Claude Code once, or agents will stall.
- **Review at the end.** Open the report (`report` tab, or `squad report --open`), read `READY.md`, confirm or change each provisional decision, then push the base branch.
- **Decide what the lead brings you:** a task that is not approved after the allowed rounds, observer suggestions marked `for V!`, or anything that needs a push, a deletion or a change outside the repository.

## Why this keeps cost down

- One brief per task. A dev reads one small file, not the spec, the task list and the history.
- One line per message. Agents read files and diffs, never each other's transcripts.
- The contract is fixed before code, so the tester and the reviewer check the same thing the dev built.
- Evidence tables. The lead verifies a row instead of re-deriving what the dev did; `squad done` refuses a report with a missing or failed row.
- The cheap seats collect the evidence and watch; the expensive seat only decides.
- Failing work never reaches the review.
- Tasks own named files, so devs never collide; the brief names the consumers, so a change does not break a neighbour unseen.
- One heavy run at a time, through `squad heavy`: first come, first served, with an owner and a time limit. Parallel full runs on one machine make every run slower and turn slow tests into false failures.
- Findings are written per class, and a fix round from round 4 runs on the stronger model.
- The lead reacts to events instead of polling. squad tells it when a seat finishes or gets into trouble.

Idle agents cost nothing. For a one-file change, use one agent; a team pays off on work that splits into several independent tasks.

## First run of a project

Claude asks once whether to trust a new repository. `squad up` starts one seat, holds the others while the dialog is open, and names the pane. Answer it, then run `squad up` again; it starts the rest. After that the project starts with no dialogs: squad gives every seat write access to `.team/` and the repository's `.git`, and gives the lead and the observer read access to the devs' worktrees.

## Troubleshooting

| Symptom | What to do |
|---|---|
| "this herdr session is not '…'" | Each repository has its own session. Run `squad up` from a terminal outside herdr, or `herdr session attach <name>` and `squad up` there. |
| A seat "did not become ready" | herdr's error is printed above it. Usually the agent shows a first-run dialog (trust this folder, sign in): open its pane, answer it, then `squad up` again. |
| A seat shows `login` on the board | Its session lost its sign-in. Open its pane and run `/login`. |
| A seat shows `stalled` | It has an open task and does nothing. The lead was told; read its pane (`squad herdr agent read <seat> --source visible`). |
| "an agent named … is already running" | Another team runs in this herdr session. Each repository needs its own: run `squad up` from outside herdr. |
| `squad heavy` waits a long time | `squad heavy --status` names the owner and the queue. A lock whose process is gone is cleared by the next caller. |
| An agent lost track | Tell it to read `.team/PROTOCOL.md` and its role file again. |
| A seat rejects `--effort` | Check the levels your Claude Code accepts with `claude --help`, and change the seat line. |

## Status of this project

Version 0.9.0 (squad v2). This version adds the GPT reviewer, the tester's contract, the observer, the report page, the lead's GPT consult, `squad heavy`, `squad dispatch`, `squad merge`, the gate in `squad done`, one herdr session per repository and resume. `test/smoke.sh` covers squad's own logic against a stand-in for herdr, Claude and Codex.

Not yet run end to end with real agents in this shape. Not verified on real herdr: the start of a session from outside herdr (the team is started through herdr's API while `squad up` attaches the session), and resume of a Codex seat through `herdr agent start … -- resume <id>`. Version 0.7.0 ran end to end on herdr 0.9.3 with its earlier team.

Known limits:

- Containers per seat are not used yet: all seats share one machine and one heavy lock. See [docs/ROADMAP.md](docs/ROADMAP.md).

- Agent arguments cannot contain quoted spaces.
- Panes are stacked by repeated splitting, so with many seats the lower panes are small; resize them in herdr.
- A Codex seat resumes only when no other Codex seat shares its folder.
- The report's cost is in percentage points of Claude's 5-hour window, not tokens.

## Contributing

Run `bash test/smoke.sh` and `shellcheck -S warning bin/squad install.sh test/smoke.sh` before sending a change (CI runs both, also under bash 3.2). The role prompts in `templates/roles/` matter as much as the script.

## License

MIT
