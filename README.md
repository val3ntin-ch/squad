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

**No seat waits on a prompt nobody answers.** The reviewer runs Codex with `-a never`: an action that would need approval is refused, never asked, and the reviewer notes what it could not check. The observer runs Claude with `--permission-mode dontAsk` and a short allow list (its own folder, read commands). Devs and the tester keep your own permission settings. `squad dispatch` sends a task only when the seat shows its prompt and no menu, and checks that the turn started. A dispatch to a busy seat waits in a queue and clears nothing. A seat is busy while it works, while its own heavy run is alive, while it waits in the heavy queue, and while it waits for its own background work (a Claude seat's Stop hook records this at each turn end, and the reading counts for one hour).

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
- **Resume.** After a restart (herdr, the Mac), `squad up` brings every seat back with its own conversation: Claude seats with `--resume <their session>`, Codex seats with `codex resume <their session>`. A Claude seat records its current session at every start, `/clear` and compaction (a SessionStart hook passed with `--settings`; the same file has the Stop hook that records the seat's background work). The lead and the observer then get one line: check the heavy lock, the queue and uncommitted work. `squad up --fresh` starts new conversations instead.

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
| `squad tokens` | Per seat and per task: the model calls and the input, cache-read, cache-write and output tokens, read from the agents' own session files (numbers only). A task's part of a seat is what the seat used from its dispatch to its report. A seat or a part with no session file shows `not measured`, never 0. The report's Cost tab shows the same numbers per task. |
| `squad status` | Shows the seats, the spec status, the task table and the agent states. |
| `squad down` | Stops the team: closes its herdr workspace and every agent in it. Worktrees, branches and `.team/` stay. |
| `squad clean` | Removes the team's worktrees. Worktrees with uncommitted work are kept, and branches are never deleted. |
| `squad config` | Creates or shows your personal default team. |
| `squad nightly` | Shows the newest scheduled run of the full suite on GitHub for the integration branch: its date, commit, result, and the failed jobs with their URLs. It needs `gh` and the `nightly_workflow` setting; without them, or with no run yet, it says so and does nothing else. See "The fast gate and the nightly full run". |
| `squad wait-owner "<what>"` | The lead's command when the team can only wait for you: you get a notification now and a reminder every `owner_reminder_hours`; the stall alarm is silent meanwhile. `squad wait-owner --done` or a new dispatch ends the wait. |
| `squad feedback "<text>"` | Your feedback after testing: saved in `.team/FEEDBACK.md`, logged, sent to the lead, who turns it into a task or a decision. When the lead shows a dialog the command says that the line is held; `squad watch` sends it when the lead is free. |
| `squad update-conf` | Adds the settings and seats a new squad version needs to `.team/team.conf` and says what it added. `squad up` and `squad init` run it; a file that has everything is left alone. |
| `squad presets` | Lists the built-in teams. |
| `squad doctor` | Checks what is installed. |
| `squad permissions` | Once per machine: Claude Code's status line, and the Codex rules for the squad commands its seats run. |

Used by the agents (you do not need them): `squad dispatch`, `squad done`, `squad heavy`, `squad candidate`, `squad merge`, `squad notify`, `squad seen`, `squad consult`, `squad decisions`, `squad git`, `squad herdr`, `squad session-id`, `squad seat-hook`.

`init`, `new` and `config` accept `--preset NAME`. `-h` or `--help` as the first argument of any command prints the help and does nothing else (`squad herdr` passes it on to herdr).

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
- **rounds** (or **round_limit**, the same number; 5) is how many review rounds a task may take before the lead brings it to you. `squad dispatch` refuses the next round, logs `ROUND_LIMIT` and sends you one notification that names the task and its review files.
- **escalate_model** is the model a fix runs on from round 4 (`squad dispatch --escalate`).
- **observer_deep_model** is the model for an observer pass after a loss over 30 minutes.
- **consult** is the command for the lead's second opinion on a real issue.
- **heavy_timeout** is how many minutes one heavy run may hold the lock (one lock for the whole machine, in `~/.cache/squad/heavy`: teams of several repositories share it); **heavy_timeout_dev** is the shorter limit for a dev's run. A dev's run needs a clean worktree (`squad heavy` refuses uncommitted changes), runs in a snapshot of that commit (`<repo>-team/.runs/<seat>`) so the dev can keep working, and every run is its own process group, so a stop ends all of it.
- **heavy_silent_minutes** (5): a heavy run whose output and CPU time do not move for this long is stopped as hung (`HUNG`), as CI systems stop a step with no output; the hard limit stays. **idle_minutes** (5): a dev with no task for this long is told to the lead once. After 30 minutes with no task, while `TASKS.md` has tasks that are not merged, you get one herdr notification: the seat, the minutes and the number of open tasks.
- **sample_percent** is the share of the tests a dev's `squad heavy … --sample -- <runner> --shard={shard}` run takes: one fixed shard per seat and task (Anthropic's `--fast` idea).
- **owner visual** (in the shipped presets, and added to older teams by `update-conf`): you test what can be seen and give feedback; the lead decides everything else from sources and marks only a visible difference `to test by the owner`, with a `See:` line (where to look). **owner all**: every provisional decision waits for you. Your name in squad's messages and the agents' role files is "the owner"; set `owner_name <name>` in `.team/team.conf` (for example `owner_name Alice`) to have them use your name.
- **upgrade off** keeps squad from adding new settings and seats to this file. Without it, `squad up` and `squad init` run `squad update-conf`: whatever the team's preset has and team.conf lacks is added at the end, with a note; nothing that is there is changed.
- **stall_minutes**: a seat with an open task that has not worked for this long is stalled.
- **observe_minutes** is the longest gap between two observer passes. The observer gets no pass while no task is open (every dispatched task is merged or withdrawn, and no candidate run is in progress); the first event that opens work starts the timer again.
- **notice_redeliver_minutes** (15): a `DONE`, a verdict or a `BLOCKED` that the lead has not acted on is sent to the lead again this often. **notice_owner_minutes** (30): after this long without an action of the lead, you get one notification.
- **owner_reminder_hours** (4): how often `squad wait-owner` reminds you while the team waits for you.
- **notify_os** (on): a notification to you is also an operating-system notification (macOS, through `osascript`). **notify_os off** keeps herdr's notification only.
- **seat_restart** (off): `squad watch` ends and starts no seat. For a seat that is gone with a task open, or that runs without its squad options, it writes the event and tells you to run `squad up`. **seat_restart on**: the watch starts such a seat again by itself, with the guards in "The watch" below.
- **flake_rerun** (1): a step of a `squad heavy --batch` run that fails is run once more alone. When it passes then, the batch goes on, and the flake is on record: a `FLAKE` event, one line in `.team/flakes.log`, and `flakes=<step>` in the candidate's receipt. `flake_rerun 0`: any failure fails the batch.
- **nightly_workflow** (empty: off): the file name of the GitHub Actions workflow that runs the full suite once a night on the integration branch, for example `nightly_workflow nightly.yml`. With it, `squad nightly` reads the newest scheduled run through `gh`, and `squad watch` asks GitHub every 10 minutes: each new run is one `NIGHTLY PASS` or `NIGHTLY FAIL` event; a failed run is one line to the lead and one notification to you, with the failed jobs.
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

Every seat shows ● working, ○ idle, ! blocked or · off, and its trouble in red (a seat whose own heavy run is alive, or that waits in the heavy queue or, with a task open, for its own background work, is busy: never stalled, never idle): `dead` (its agent is gone), `login` (a sign-in error), `blocked` (a prompt or a question: herdr shows it `blocked`, or the seat shows a dialog by one of the signs below), `stalled` (an open task and no work for `stall_minutes`). A seat that shows a dialog is `blocked`, never `stalled` and never idle: the lead's line says that the seat waits for your answer and that squad queues any dispatch to it, and you get the one "waits for you" notification. Each trouble is written to `events.log` under the watch's own event name (`SEAT_DEAD`, `SEAT_LOGIN`, `SEAT_BLOCKED`, `SEAT_STALLED`; a plain `BLOCKED` is only what a seat reports with `squad done`, so the watch's finding never closes a seat's task) and told to the lead once.

The watch also acts on each seat by itself, also while other seats work. squad never answers a seat's question or permission prompt; it only tells you (a herdr notification, and an operating-system notification with `notify_os on`). It types nothing into a seat that shows a dialog. A seat shows a dialog when any of three signs says so: herdr shows it `blocked`; a Claude seat's hook recorded a permission request or a question that is still open (herdr shows a seat with a question as `idle` in a narrow pane and as `blocked` in a wide one); or its visible screen shows a menu. The screen sign is the shape of a dialog, not its words: a dialog footer ("Esc to cancel", "Enter to select", also wrapped by a narrow pane) in the last lines below the last horizontal rule, or a selected numbered row (`❯ 1. …`) as the last prompt-marked line with the next numbered row below it. The words of a dialog in a seat's last message, or in an echoed prompt, are no sign: an idle seat is not held because of them. For such a seat, `squad dispatch` types no `/clear` and no task: the task waits in the seat's queue (`DISPATCH_QUEUED`), the command says "<seat> shows a dialog or a question: <task> waits and is sent when it is answered", and the task goes out when the dialog is gone. squad's own messages to the lead (a seat in trouble, an idle dev, a team stall, a queued dispatch that was not sent, a `squad done` notice, `squad feedback`, a consult result) wait and go out at a later tick. `squad notify` skips such a seat and prints its name, `squad plan` refuses, and with `limit_fallback` such a seat is not switched to the other model (you are told).

- **A seat waits for you.** A Claude seat's hooks report a permission request or a question at once; any seat that herdr shows `blocked` for 5 minutes is reported from its screen. The notification names the seat, its task and the first line of the question. The hook's record ends when the dialog is over: the tool call it asked for ended (it ran or it failed; another call of the same tool, in parallel or in a subagent, does not end it), the seat's turn ended, a prompt was submitted or the session started again. A record older than 2 minutes also ends when the seat ended a turn or reported after it. Escape closes a dialog and no hook runs, so the seat's screen can also end a record: when the record is older than 20 seconds, herdr does not show the seat `blocked`, and the screen shows the seat's prompt line and no menu on two checks at least 10 seconds apart, the record ends, your alert for that wait ends, and a queued dispatch goes out. A screen that cannot be read, or shows anything else, keeps the record. A seat with no record that herdr shows idle while its screen shows a menu is reported after 5 minutes, like a `blocked` seat. A turn that ends on a usage limit or a sign-in error is reported at once. The hooks start the notification in the background and return, so the seat's dialog does not wait for it.
- **A seat is stuck.** A `stalled` seat or a seat with a sign-in error is told to you, not only to the lead.
- **A seat is gone or runs without its squad options** (after a herdr restart, a seat can come back without its role, its settings and its permission mode). The cases: a seat that is gone when it has an open task (the lead always), and a seat without options when it is idle. With `seat_restart off` (the default) the watch types nothing: `events.log` gets a `SEAT_GONE` or `SEAT_NO_OPTIONS` line and you are told once per case ("<seat> is gone: run squad up", "<seat> runs without its squad options: end its agent in its pane when its work is finished, then run squad up"; the reminders of a condition that still holds apply). With `seat_restart on` the watch starts the seat again with its full options, as `squad up` does. Before it types anything, the watch reads the seat again and goes on only when the seat is free: idle at an empty prompt with no dialog, with no heavy run, no place in the heavy queue, no background work and no dispatch that is being delivered; for a seat that is gone, its pane shows only a shell and herdr sees no agent there. Otherwise it types nothing and looks again at the next tick; you are told when that stays so for 10 minutes. `events.log` gets a `SEAT_RESTART` line. With `seat_restart on` the lead does not get the "is dead … run 'squad up'" line for a gone seat (the `SEAT_DEAD` event is still logged); it gets the line only when squad has stopped restarting that seat. A lead or a dev with an open task gets the task again. A seat is restarted at most once in 10 minutes; after 3 restarts in one hour squad stops, tells you, and starts that seat no more until you run `squad up` or the seat is seen running again. You are also told when a seat ended and its new start failed. A seat whose pane is closed is not started: you are told to run `squad up`. A Claude seat that starts without its options also tells you at once from its own start hook (once per seat), because the watch may not run after a herdr restart.
- **A notice waits for the lead.** Each `DONE`, verdict and `BLOCKED` is kept until the lead acts on the task: its own event for the task, a new dispatch of it (a contract request that squad sends to the tester does not count), or `squad seen <task>` when the notice needs no action. A candidate's `PASS` ends with its merge or a newer candidate; a candidate's `FAIL` ends with a dispatch of one of its tasks or a newer candidate. Until then the line is sent to the lead again every `notice_redeliver_minutes`, and you are told once after `notice_owner_minutes`; after that it is sent 3 times more and then no more. Nothing is sent while the lead shows a dialog: a `squad done` whose first line is held says so, and the line goes out at the first tick with the lead free.
- **The team waits for you** (`squad wait-owner`): you are reminded every `owner_reminder_hours`, and the team-wide stall alarm is silent. Only the lead (or you, at a terminal) sets this wait.

A notification for a condition that still holds comes again every 30 minutes, at most 3 times, and stops when the condition ends (the team-wide stall: when a new event comes). The Claude seat hooks, the Stop hook that records a seat's background work among them, are also written to each team worktree's `.claude/settings.local.json` (kept out of git through `.git/info/exclude`), so a seat that herdr resumed without options still reports; your own hooks in that file are kept. A running `squad watch` starts the new `bin/squad` by itself when the file changes (an update), and starts again when `.team/team.conf` changes, so a changed setting (for example `seat_restart on`) is used without a restart; a `team.conf` that does not load is not used.

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
lead   adjudicates each finding, checks the screens: squad done lead T-001 APPROVE (it records the exact commit) — or sends it back
lead   writes tasks/CANDIDATE-1.md (its rows) and tasks/CANDIDATE-1.checks (its commands), then squad candidate CANDIDATE-1 T-001 T-002
lead   squad dispatch tester CANDIDATE-1       ▶ tester runs squad heavy tester CANDIDATE-1 --batch …checks on that commit; a task's own PASS does not count
lead   after the tester's PASS on CANDIDATE-1: squad merge CANDIDATE-1  (the integration branch becomes exactly that commit)
tester a failed candidate: squad done tester CANDIDATE-1 FAIL --task T-002   (the task it holds responsible; the receipt names the failed step and its log)
lead   squad candidate CANDIDATE-2 --from CANDIDATE-1 --without T-002  ▶ the other tasks go on with no new review; T-002 goes back to its dev
lead   a real issue: squad consult "<question>" ▶ GPT brainstorms from official sources; both views go into DECISIONS.md
observer  measures every pass, writes observer/NOW.md and SUGGESTIONS.md; the lead adopts or rejects each one
lead   converge, LESSONS.md, READY.md ──▶ you   (only when everything is green)
```

A team needs a tester seat to merge: `squad merge` takes only a candidate that the tester passed (add a `tester` seat to team.conf first).

### The fast gate and the nightly full run

One machine has one test lock, and a full suite on every candidate makes that lock the team's queue. With `nightly_workflow` set, each candidate runs only the fast checks (lint, types, build, unit tests, the tests of the changed parts), and the full suite runs once a night in GitHub Actions on the integration branch. The workflow is your project's own file; squad only reads its result. An example, `.github/workflows/nightly.yml` (put your project's commands in it; `team/integration` is the default `base`):

```yaml
name: Nightly full suite
on:
  schedule:
    - cron: "0 2 * * *"   # GitHub runs a schedule on the default branch only
permissions:
  contents: read
jobs:
  full-suite:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
        with:
          ref: team/integration   # the team's integration branch
      - run: npm ci
      - run: npm test             # the full suite
```

Then `nightly_workflow nightly.yml` in `.team/team.conf`. `squad nightly` prints the newest scheduled run and its failed jobs; the lead makes a fix task for each failure.

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
| `receipts/CANDIDATE-<n>/` | The runner's `receipt` of a candidate run (the commit, each step's exit code, the flaky steps, and one `failed=` line for each failed step: the step, its exit code and its log file) and one log per step (`step-<i>.log`; `step-<i>.first.log` is the failed first run of a flaky step). Kept after a failure too. |
| `flakes.log` | One line per batch step that failed once and passed when run again alone. |
| `observer/NOW.md`, `observer/SUGGESTIONS.md` | What is wrong now and what it costs; ranked changes with their evidence and status. |
| `LESSONS.md` | At the end: each finding that came back, and the cheapest change that stops it next time. |
| `READY.md` | The lead's final summary: what to look at, rows not verified, decisions open for you. |
| `report.html` | All of the above on one page (`squad report`). |

**Decisions are yours; the team does not wait.** The lead decides provisionally, from the repository first and then from official sources (the library's documentation for the installed version, standards bodies such as W3C, WCAG, WHATWG and OWASP, release notes, well-maintained projects). On a real issue (a finding that comes back, a task at round 3, sources that disagree, architecture, a dependency, accessibility, security or data) it writes its own options, asks GPT for an independent brainstorm, and compares. Every provisional decision is listed for you in `READY.md` and in the report's Decisions tab before anything reaches `main`.

**QA comes first.** The tester agrees the acceptance contract before code is written: exact commands, thresholds, and the states the brief forgot. Every row ends in one of five results: pass, fail, pending, unavailable, inconclusive. Only pass counts; everything else is listed for the lead and for you.

**Fresh eyes on every diff.** GPT reviews with a fresh context and looks for the whole class of a defect, not one place at a time. Re-reviews read only the fix. The lead decides on each finding and does the visual check.

**Fresh facts only.** No seat acts on memory or on an old context. The files and git are the truth and are read again before each step; an API, a version or a flag is read where it is defined, never recalled; every task starts from a cleared context.

The lead pushes only the integration branch (`squad git push`, no arguments, after each merged candidate); `main` and production stay yours. Your own checkout is never touched: all work happens in worktrees in `<repo>-team/`. `squad init` adds `.team/` to `.git/info/exclude`, so team files stay out of your commits.

## Plan before you build

Add a `planner` seat (and a `critic` seat, GPT) to team.conf, then `squad start-seat <planner>`: both open in a plan tab.

1. `squad plan "<goal>"` (a project) or `squad plan "<goal>" --feature` (one feature). The planner reads the official documentation of the versions in use and proves each claim on the real platform, with a proof file in `.team/plan/proofs/`. For a feature, the later commands name it: `--critique F-<n>`, `--check F-<n>`, `--approve F-<n>`.
2. The planner runs `squad plan --critique`: the critic lists every claim it cannot verify, and the planner answers each one.
3. `squad plan --check` must say `PLAN OK`; then the planner tells the lead.
4. You read `.team/PLAN.md` (or `.team/plan/F-<n>.md`), decide its open decisions, and run `squad plan --approve`. The team builds only an approved plan.

## Your part

- **Write the goal** in `.team/GOAL.md`. Say where the rules, the design and the references are.
- **Answer permission prompts and sign-in errors.** squad shows them in red on the board and tells the lead; the lead tells you. Allow git, your package manager and your test commands in Claude Code once, or agents will stall.
- **Review at the end.** Open the report (`report` tab, or `squad report --open`), read `READY.md`, confirm or change each provisional decision, then merge the pushed base branch into `main`.
- **Decide what the lead brings you:** a task that is not approved after the allowed rounds, observer suggestions marked `for the owner`, or anything that needs a push of another branch, a deletion or a change outside the repository.

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
| A seat shows `stalled` | It has an open task and does nothing. The lead and you were told; read its pane (`squad herdr agent read <seat> --source visible`). |
| "squad: <seat> is gone" | Run `squad up`: it starts the seat with its full options. With `seat_restart on` in `team.conf` the watch does this by itself. |
| "squad: <seat> runs without its squad options" | `squad up` leaves a seat that runs as it is. Let the seat finish its work, end its agent in its pane (`/exit`; Codex: `/quit`), then run `squad up`: it starts the seat with its full options. With `seat_restart on` in `team.conf` the watch does this by itself. |
| "squad: <seat> does not stay up" | With `seat_restart on`: squad restarted the seat 3 times in one hour and stopped. Read its pane, fix the cause, then run `squad up`. |
| "squad: check <seat>'s options" | With `seat_restart on`: squad restarted the seat and still cannot see its squad options in its process. Read its pane; `squad up` after you close its agent starts it with its options. |
| "an agent named … is already running" | Another team runs in this herdr session. Each repository needs its own: run `squad up` from outside herdr. |
| `squad heavy` waits a long time | `squad heavy --status` names the owner and the queue. A lock whose process is gone is cleared by the next caller. Each wait is in `events.log`: `HEAVY_WAIT` when it starts, and `waited=<seconds>s` in the run's `HEAVY_START`. |
| `squad candidate` says the number is used | One number is one commit. Build the candidate again with the next free number, which the message names. |
| An agent lost track | Tell it to read `.team/PROTOCOL.md` and its role file again. |
| A seat rejects `--effort` | Check the levels your Claude Code accepts with `claude --help`, and change the seat line. |

## Status of this project

Version 0.9.1 (squad v2). 0.9.1: the owner tests what can be seen and gives feedback (`owner visual`, `squad feedback`, the report's To test tab). This version adds the GPT reviewer, the tester's contract, the observer, the report page, the lead's GPT consult, `squad heavy`, `squad dispatch`, `squad merge`, the gate in `squad done`, one herdr session per repository and resume. `test/smoke.sh` covers squad's own logic against a stand-in for herdr, Claude and Codex.

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

squad is released under the **Functional Source License, Version 1.1, MIT Future License** ([FSL-1.1-MIT](LICENSE), part of [Fair Source](https://fair.io/)):

- **Free to use** for any purpose — your own projects, your company's work, teaching, research — and to read, change and share.
- **Not allowed:** offering squad, or a product or service built from it, in competition with squad.
- **Each version becomes MIT** two years after its release.
- **Versions released before 17 Nov 2026** stay under the MIT License they were released with.

The exact terms are in [LICENSE](LICENSE).
