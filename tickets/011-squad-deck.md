# 011 · Squad Deck: named agents and five clear tabs in herdr
Status: Approved (V!, 14 Nov 2026)
Size: L — split into 011a, 011b, 011c (one PR each, in this order)

## Goal
V! sees at a glance, in herdr, who works on what, what it is doing now, how far each task is,
what is proven, what costs time, and what V! must test. The look is the one V! approved on
14 Nov 2026: `docs/design/squad-deck-team.html` (team tab) and `docs/design/squad-deck-tabs.html`
(review, changes, observer, report).

## Shared rules (all three parts)
- Plain terminal text only: colours, box lines, block bars, Braille spinners. No new app or runtime;
  the tabs stay squad's own bash programs (`squad watch`, `squad report --live`, …).
- One look in every tab: the same header line (project, step, progress, lock, other teams, usage),
  the same agent names, colours and hexagon badges, the same key bar at the bottom.
- Every number comes from squad's files: `events.log`, `TASKS.md`, briefs, contracts, reports,
  `DECISIONS.md`, `FEEDBACK.md`, `observer/`, git in the worktrees, the heavy lock, herdr's agent list.
- Reduced motion: no spinner or pulse when `NO_MOTION=1` or the terminal says so.
- Works at 120 columns and up; below that, columns stack.

---

## 011a · Names, herdr sidebar, notifications, team tab
Size: M

### Scope
- In: `name <seat> <Name> <colour>` lines in team.conf (update-conf proposes Atlas, Nova, Rook, Iris,
  Vera, Sol, Owl for the default preset; V! can rename); herdr sidebar labels for each seat
  (`herdr pane report-metadata --display-agent "<Name> · <role>" --state-label …`); herdr
  notifications for: a merge, a failed test run, a new item to test, a seat that needs V!
  (sign-in, permission); the **team tab** as approved: agent list with live labels on the left,
  the mission view of the selected agent's task on the right (header with task and clock, step track,
  proof gauge with acceptance rows, live activity and health, timeline, decisions on the task).
- Out: the other four tabs (011b, 011c).

### Done when
- [x] team.conf `name` lines: names and colours show in the team tab, herdr's sidebar and every
      message squad sends; a team without them gets the proposed names from update-conf.
- [x] herdr's sidebar shows each seat as "<Name> · <role>" with a live state label (DEV, LOCK #2,
      TEST 11m, REVIEW, 2 OPEN); a seat that leaves its task loses the label.
- [x] A herdr notification (title, body, sound) arrives once for each merge, failed run, new
      "to test" item and seat that needs V!; `notify off` in team.conf turns them off.
- [x] The team tab matches the approved mockup: ↑↓ picks an agent, the mission view shows its task
      (steps with times, acceptance rows ✔ ◐ ○ from contract and newest report, live activity from
      herdr's title, files changed / last commit / heavy runs / lock place from git and the lock,
      the next blocker, the task's timeline and decisions), and keys b c r d t f work.
- [ ] Smoke tests for each item (rendered text checked with the herdr stand-in); shellcheck; bash 3.2.

---

## 011b · Review and changes tabs
Size: M

### Scope
- In: **review tab**: "Vera tests the work of <devs>" with one row per task in the run (agent name and
  colour), elapsed against the limit, the hung check, each suite with bar, time and count, known
  flaky tests; Sol's queue and last verdicts by developer; contracts Vera owes and for whom; the two
  panes as thin rows (`v`, `s` open them). **Changes tab**: task branches against the integration
  branch (agent, size, ahead/behind, merges clean or conflicts, two tasks on one file), candidate
  history, and at full height the selected branch's files with a diff preview; `g` opens lazygit as
  a herdr popup; read-only (never merges or pushes).
- Out: observer and report (011c).

### Done when
- [ ] The review tab matches the approved mockup; every line names the developer whose work it is.
- [ ] Suite rows come from the tester's run log through `squad heavy` (one line per suite with its exit
      code and time); a run without that structure shows the whole run as one row.
- [ ] The changes tab matches the approved mockup, at full height; merge state comes from
      `git merge-tree`; `g` opens lazygit full screen; nothing in the tab writes to git.
- [ ] Smoke tests; shellcheck; bash 3.2.

---

## 011c · Observer and report tabs
Size: M

### Scope
- In: **observer tab**: minutes lost today by cause, open findings with severity and cost, the
  suggestions board (open / for you / adopted) with the selected suggestion's detail at full height
  and keys a / x / v / ⏎, each agent's day as a heat strip, Owl's pane as a thin row. **Report tab**:
  "to test by you" with coloured chips (developer and task, kind, story, size, light/dark, how to
  find the state), `y` (records "looks right" as feedback) and `f` (feedback), items that just became
  ready marked new; the night as a timeline with task ids on the bars, all seats, merges and "now";
  numbers with their colour and symbol; decisions taken by the team with agent and kind; the
  step-3/4 reminder.
- Out: the HTML report page keeps its tabs; it gets the same colours later.

### Done when
- [ ] The observer tab matches the approved mockup; a, x, v change the suggestion's status in
      `observer/SUGGESTIONS.md`.
- [ ] The report tab matches the approved mockup; `y` writes a "looks right" feedback entry for the
      selected decision, `f` opens a one-line prompt and calls `squad feedback`.
- [ ] Decision kind (look, contrast, layout, API, test, tokens, process) comes from a new optional
      `- Kind:` field in DECISIONS.md; without it the chip is left out.
- [ ] Smoke tests; shellcheck; bash 3.2.

---

## Assumptions & open questions
1. Not verified yet: how herdr draws `--display-agent` and `--state-label` in its sidebar; 011a starts
   with a short test of both. If herdr does not show them, the names stay in squad's own tabs only.
2. Notifications use herdr's `notification show`; macOS may ask V! once to allow them.
3. The mockups' times and counts are illustrative; the real tabs read the files.
4. Next ticket: 012 (planner, plan tab, final end-to-end tests), after 011a–c.
