# 012 · Planner: research and proof before any work starts
Status: Approved (the owner, 16 Nov 2026)
Size: M (≤ 1 day)

## Goal
No project, feature or mockup starts on an invented promise. A planner seat does the research
first: official sources, the real limits of the target platform, and a proof for each claim.
Lesson from the Squad Deck: the HTML mockups promised a look that a terminal cannot draw, and
nobody checked that before days of work.

## Scope
- In:
  - A new seat role `planner` (Claude Fable 5.2) and a new seat role `critic` (GPT Sol 6.1 on Codex,
    `-a never`), with their role files; both run in the herdr tab "plan", side by side (the owner, 16 Nov 2026).
  - A new command `squad plan "<goal>"`: the planner researches and writes `.team/PLAN.md`.
  - A critique step: the GPT critic seat reads the plan and the proofs and lists every claim it
    cannot verify, ending with `ITEMS: <n>`. The planner answers each item.
  - A check, `squad plan --check`, that refuses a plan with an unproven claim.
  - A gate: `squad dispatch` refuses work while the plan is not approved by the owner. the owner approves with
    `squad plan --approve`.
  - The planner seat in the default preset; `squad update-conf` adds it to existing teams.
- Out (not in this ticket):
  - A screen drawn by squad for the plan (the owner reverted the drawn screens on 16 Nov 2026); the plan tab shows the planner's own pane.
  - The Linear mirror of tasks.
  - The final end-to-end tests (own ticket).
  - Changes to project A's running work. Project A gets the planner only through `update-conf` after the owner's OK.

## Done when  ← the user approves exactly this list
- [ ] `squad plan "<goal>"` starts the planner, and it writes `.team/PLAN.md` with these sections:
      Goal; Platform and versions; Sources (each: official URL, date read); Limits of the platform;
      Feasibility table (claim | official source | proof | result); Risks; Tasks; Open decisions for the owner.
- [ ] Every proof is a file in `.team/plan/proofs/`: the command that was run and its output, or a
      small spike made on the real platform. A mockup row is valid only when it was made on the
      target platform (for a terminal app: a capture of a real program, not an HTML page).
- [ ] `squad plan --check` fails, and names the row, when a feasibility row has no official URL,
      no proof file, a missing proof file, or the result "unproven". It also fails while an item of
      the critique (`.team/plan/critique.md`) has no answer. It passes on a complete plan.
- [ ] `squad dispatch` refuses to start any task while `PLAN.md` is not approved, and says why;
      `squad plan --approve` (the owner only) records the approval with the date, and dispatch then works.
- [ ] A new team (default preset) has the planner and the GPT critic, both in the herdr tab "plan"; `squad update-conf` adds the seat to an older team.conf once and skips a
      team that has it. the owner sees the plan tab in a new squad.
- [ ] Smoke tests for each item above pass; shellcheck is clean; bash 3.2 runs them.

## Plan
- `templates/roles/planner.md`: the planner's rules. Research before writing: official docs,
  release notes and source of the exact versions in use; no claim without a source and a proof;
  build a small spike on the real platform for every claim about look or behaviour; write
  "unproven" when it cannot prove a claim, never guess; list each choice as an open decision for the owner
  with options and a recommendation.
- `templates/PLAN.md`: the plan template with the sections above.
- `bin/squad`: `cmd_plan` (start or brief the planner seat, then run the critique through
  `squad consult`), `plan_check` (parse the feasibility table and the critique), `--approve`
  (records "Approved by the owner <date>"), and the gate in `cmd_dispatch`.
- `presets/*.conf` and `update-conf`: the `planner` seat line.
- `test/smoke.sh`: tests for check, gate, approve and update-conf, with the herdr stand-in.

## Tests
- Item 1: a stand-in planner run writes PLAN.md from the template; the test checks every section heading.
- Items 2–3: `plan --check` on fixture plans: one complete (passes); one per failure case (no URL,
  no proof file, "unproven", an HTML mockup for a terminal platform, an open critique item), each fails and names the row.
- Item 4: dispatch before approval is refused (exit code and message); after `plan --approve` it starts.
- Item 5: init with the default preset has the seat; update-conf adds it once; a second run changes nothing.
- Item 6: the existing CI (ubuntu, macOS, bash 3.2).

## Assumptions & open questions
- Decided (the owner, 16 Nov 2026, with the ticket): the planner is Claude Fable 5.2; GPT Sol 6.1 critiques.
- Decided (the owner, 16 Nov 2026, with the ticket): a new feature in the middle of a project gets its own
  plan (`squad plan`); small fixes inside an approved task do not.
- Open decision for the owner: what happens to the Squad Deck code on main (revert both PRs, only the
  screens, or nothing). This ticket does not depend on it.
- Assumption: "official sources" means the vendor's own docs, release notes, specs (for example
  W3C, WAI-ARIA) and the source code of the exact version in use; blog posts count only as leads.
