# 000 · squad v2 (index)
Status: Approved (V!, 13 Nov 2026)
Size: L — split into the tickets below

## Goal
Remove the measured losses of the hive run (18 h, 27 tasks, average 2.6 review rounds,
11 tester FAILs, a 72-min stop nobody saw), make QA independent and cross-model, and show
V! what the team does and why, in one place.

## Tickets (all on branch `v2`, one PR at the end)
| # | Title | Audit rows | Size |
|---|---|---|---|
| 001 | Machine rules in the script: lock, dispatch, ledger, Stop hook switch | 1, 2, 3, 4 | M |
| 002 | QA and review: GPT reviewer, contract first, five result states, done gate | 6–14 | M |
| 003 | Observer seat and tab: stuck seats, timeline, suggestions | 5, 15, observer | M |
| 004 | Lead on a real issue: GPT consult with official sources, decisions as HTML | 16, consult, HTML | M |
| 005 | Learning and cost: compound step, converge, cost log, rule budget | 17–20 | S |
| 006 | One herdr session per repository, and resume where the team stopped | V! 13 Nov | M |

Order: 001 → 006 → 002 → 003 → 004 → 005. 003 and 004 read the ledger that 001 writes;
006 comes early because every later test run restarts the team.

herdr tabs in v2: `team · review · changes · observer · report`.

## Report page (shared by 003 and 004)
`squad report` writes `.team/report.html`: one static page, no server, no network.
Tabs: Decisions · Observer · Timeline · QA · Cost. Built from files that stay plain
text and easy to follow by hand:
- `.team/events.log` — one line per event (ledger, from 001)
- `.team/DECISIONS.md` — one block per decision (from 004)
- `.team/observer/NOW.md` and `.team/observer/SUGGESTIONS.md` (from 003)
- `.team/consult/<n>.md` (from 004)

## V!'s decisions (13 Nov 2026)
1. Stop/verify hook: off in team worktrees, opt-in line `verify_hook off` (recommended option).
2. GPT reviewer comes first; the lead adjudicates and does the visual check (both review).
3. The lead decides provisionally and continues; every provisional decision is listed for V!
   in READY.md and the Decisions tab before any push.
4. GPT seats (reviewer and consult): `gpt-6.1-sol`, reasoning effort medium.
5. Observer: Sonnet for the regular passes; Opus only when a pass finds a loss over 30 min.
