# 009 · The owner tests the visual items and gives feedback
Status: Draft — waiting for approval
Size: S

## Goal
V!'s role in a squad team is to test what can be seen and give feedback (V!, 13 Nov 2026). The lead
decides everything the eye cannot see, from sources, and never waits for V!. V! gets one clear list
of what to test, and one command to give feedback that the team turns into work.

## Scope
- In: team.conf `owner visual` (default for the shipped presets; `owner all` keeps the old rule);
  lead role text for both modes; a "To test" list in the report (the visual decisions that wait,
  each with the place to look); `squad feedback "<text>"`; README.
- Out: changing hive's or tonus's running teams by hand (they get it at their next `squad up`
  through update-conf); a feedback form in the HTML page.

## Done when
- [ ] With `owner visual`, the rendered lead role says: decisions the eye cannot see are the lead's
      and final once sourced; only a visible difference is "To test by V!", with where to see it
      (story, page or screen) and its expected value; with `owner all` the v2 text stays.
- [ ] A decision block may carry `- See: <story id, URL or screen>`; the report's "To test" list
      (HTML tab and live view) shows each decision with status `to test by V!` and its See line.
- [ ] `squad feedback "<text>"` (or `squad feedback --file <path>`) appends a dated entry to
      `.team/FEEDBACK.md`, logs `FEEDBACK` in events.log and tells the lead in one line; the lead
      role turns each entry into a brief or a decision, and marks the entry done with the task id.
- [ ] `squad update-conf` adds `owner visual` to older teams; the shipped presets have it.
- [ ] `bash test/smoke.sh` and `shellcheck` pass under bash 5 and 3.2.

## Plan
- `bin/squad`: `owner` in load_conf and render (`$OWNER_MODE` sections), `cmd_feedback`,
  report "To test" (decisions_tsv + the See field), `DECISION_FIELDS` unchanged (See optional).
- `templates/roles/lead.md` ("Who decides" in two variants), `templates/FEEDBACK.md`, presets, README.

## Tests
- smoke: rendered lead role per mode; report lists a `to test by V!` decision with its See line and
  not a final one; `squad feedback` writes the file, the event and the lead line; update-conf adds
  `owner visual`.

## Assumptions & open questions
1. "Visual" means anything the eye can see in the product: the look, layout, motion, copy on screen.
2. GLOBAL.md's "all decisions belong to V!" still holds outside squad teams (architecture, product,
   privacy, legal decisions in V!'s own sessions).
