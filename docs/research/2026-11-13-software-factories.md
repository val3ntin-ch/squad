# What the best software factories do, and what squad takes from them

Research of 13 Nov 2026. A research agent opened each source itself (GitHub files through
`gh api`, web pages through WebFetch or curl). Quotes from the Anthropic, Cursor, GitHub,
OpenHands, Devin, Factory and Bazel pages come from WebFetch's extraction, not raw HTML.

| # | Solution | Verdict | Sources and quotes | In squad |
|---|---|---|---|---|
| 1 | Verify a frozen, known state | Confirmed | agent-engineering `references/workflow-contract.md` (2026-10-27): "record the candidate: revision plus content identities (hashes or diffs) … and dirty files"; "HEAD and Git status alone do not establish unchanged contents." superpowers `subagent-driven-development` (2026-11-03): "Record BASE (`git rev-parse HEAD`) before dispatching". Gas Town README: "a Bors-style merge queue — polecats never push directly to main". | 007: a dev's heavy run refuses uncommitted changes and records the commit. **Stronger option (open):** run from a detached snapshot of the commit. |
| 2 | Agents run a sample; the full suite runs once | Confirmed (Anthropic); Factory not verified | anthropic.com/engineering/building-c-compiler (5 Feb 2026): "a default `--fast` option that runs a 1% or 10% random sample"; "deterministic per-agent but random across VMs"; "the task verifier is nearly perfect"; "Claude can't tell time and, left alone, will happily spend hours running tests". | Tester owns the full run; 007: dev limit 10 min. **Open:** a deterministic sample mode for devs. |
| 3 | Isolation instead of shared locks | Confirmed for coordination locks | cursor.com/blog/scaling-agents (14 Jan 2026): "Twenty agents would slow down to the effective throughput of two or three"; cursor.com/blog/self-driving-codebases: "They work on their own copy of the repo". Per-agent VMs or sandboxes: Claude Code on the web ("each session runs in an isolated, Anthropic-managed VM"), Cursor cloud agents, Devin ("Every session starts from the same clean state"), OpenHands ("Docker sandbox (recommended)"). | One Mac shares CPU and RAM, so squad keeps one heavy lock. **Open decision for V!:** sandboxes or more machines. |
| 4 | Batch, then bisect a failure | Confirmed (bors-ng, Gas Town); GitHub removes the failing PR instead | bors-ng README: "it splits the batch into two batches"; Gas Town: "bisects to isolate the failing MR, merges the good ones"; GitHub merge queue: rebuilds without the failing PR, with a "status check timeout". | v2 protocol: the tester finds the failing task; the others go into the next candidate. |
| 5 | Stuck-agent detection from terminal state | Confirmed | Gas Town `gt feed --problems`: "GUPP Violation", "Stalled", "Zombie"; ccmanager: "Waiting", "Busy", "Idle", and "Status Change Hooks". | v2: `dead`, `login`, `blocked`, `stalled`; the lead is told once. |
| 6 | Leases with a time limit; a build slot | Confirmed | mcp_agent_mail_rust README: "Advisory file reservations instead of hard locks"; "Build Slots: `acquire_build_slot`, `renew_build_slot`, `release_build_slot`"; "Reservations and build slots expire". | `squad heavy` is the same idea as a build slot (owner, time limit, dead owner cleared). File leases: not yet. |
| 7 | The runner owns timeouts and the process group | Partly confirmed | Bazel Test Encyclopedia: "The runner must not report the test as passing after sending a signal to the test process or any children thereof"; "Tests may create subprocesses, but not process groups or sessions"; tag `exclusive`: "run no other test at the same time". GNU `timeout`: own process group, exit "124 if command times out". No source says "never kill by name"; that half is inference. | `squad heavy` stops the run's own process tree, TERM then KILL, exit 124. **Open:** a process group per run. |

## Open proposals from this research (decisions for V!)

1. **Run from a frozen snapshot.** A heavy run uses a detached copy of the commit, so the seat can
   keep working and no edit during the run can change what is tested (source 1). Cost: low.
2. **A deterministic sample mode for dev seats** (1–10%, seeded by the seat name), the full suite
   only for the tester (source 2). Directly attacks the 21–25 min dev holds. Cost: low, but it
   depends on each project's test runner.
3. **A process group per heavy run**, killed as a group; never a pass after a signal (source 7).
   Cost: very low.
4. **Isolation per seat** (containers or more machines) instead of one shared lock (source 3).
   Cost: high; an architecture decision.

## Not verified
How Factory's validators run tests; whether Codex cloud uses containers; any primary source that
forbids kills by name pattern; page dates of the GitHub, Bazel, OpenHands, Codex and Factory pages.
