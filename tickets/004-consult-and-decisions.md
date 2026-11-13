# 004 · Lead on a real issue: GPT consult with official sources, decisions as HTML
Status: Approved (V!, 13 Nov 2026)
Size: M

## Goal
When the lead meets a real issue, it does not decide alone from memory: it asks a top GPT
model with web search for an independent brainstorm from official sources (W3C, vendor
docs, standards), compares it with its own, decides provisionally and logs why. V! reads
every decision, with both views and the sources, in one HTML page.

## Scope
- In: `squad consult`; when the lead must use it; a fixed decision format; the Decisions tab
  of `squad report`; "provisional" decisions listed for V! in READY.md.
- Out: GPT never edits code or team files; nothing is pushed.

## Done when
- [x] `squad consult "<question>" [files...]` runs `codex exec --search` read-only with the
      command `consult` from team.conf (default `codex --search exec -m gpt-6.1-sol -c model_reasoning_effort=medium`), a prompt that requires official sources with
      URLs and at least two options with trade-offs, and writes `.team/consult/<n>.md`; it
      logs `CONSULT <n>` in events.log.
- [x] Lead role: a real issue is one of — the same finding twice, a task at the round cap,
      BLOCKED twice, sources that disagree, or a decision about architecture, a dependency,
      accessibility, security or data. For each, the lead writes its own options first,
      then runs `squad consult`, then decides.
- [x] Each decision in DECISIONS.md has: id, time, question, options, Claude's view, GPT's
      view (consult file), sources (URLs, version checked), decision, why, status
      (`provisional — open decision for V!` or `final`); `squad done`-style check:
      `squad decisions --check` fails on a block with a missing field.
- [x] `squad report` Decisions tab lists every decision with its fields, filter by status,
      and links to the consult file; READY.md lists every provisional decision.
- [x] `bash test/smoke.sh` and `shellcheck` pass.

## Plan
- `bin/squad`: `cmd_consult` (codex exec, `--sandbox read-only`, `-o` to the consult file,
  `-C` integration worktree); `cmd_decisions --check`; `cmd_report` Decisions tab.
- `templates/DECISIONS.md` with the block format; `templates/roles/lead.md` "When to consult"
  and "Who decides" (provisional by default).
- `templates/consult-prompt.md`: the brainstorm prompt (sources in order: repo decisions,
  official docs for the installed version, standards bodies such as W3C/WCAG, top projects).

## Tests
- smoke: `squad consult` with a codex stand-in writes the file and the event; fails clearly
  when codex is missing.
- smoke: `decisions --check` passes a full block, fails a block without "why" or "sources".
- smoke: report HTML contains each decision id, its status and the consult link.

## Assumptions & open questions
1. **Open decision for V!:** the consult model and effort (a top GPT model, high reasoning).
   I will read what your Codex offers and propose one.
2. **Open decision for V!:** "Who decides". Recommended: the lead decides provisionally and
   continues (no waiting, as you told hive); every provisional decision is listed for you
   in READY.md and in the Decisions tab before any push.
3. Assumption: `codex exec --search` is available in your Codex 0.161.0 (`codex --help`
   lists `--search`; I will confirm it works under `exec`).

## Evidence (13 Nov 2026)
`bash test/smoke.sh`: 234 passed under bash 5 and under /bin/bash 3.2.57; `shellcheck -S warning`: clean. smoke: 'consult runs GPT Sol read-only with web search and writes the file', 'consult passes the model, the effort and read-only', 'the consult prompt carries the question, the files and the source order', 'two consults started together get their own numbers', 'decisions --check fails a block with an empty field', 'the page shows each decision with its status and the GPT consult'. Not verified: a real `codex --search exec` call.
