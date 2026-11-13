# Spec: <feature name>

Status: DRAFT  <!-- the lead sets this to APPROVED when the spec is complete enough to hand out tasks -->

## Goal

<What the human wants and why, in two or three sentences. What will be true for a user when this is done.>

## Scope

In:
- <behaviour that will exist>

Out:
- <things deliberately not done in this round>

## Design

<How it fits into the existing code: the modules involved, the data flow, the interfaces between the parts that different devs build. Name real files. Keep it to what a dev needs to do a task without re-deriving the design.>

## Decisions and constraints

- <a choice that was made, with its reason and its source, so nobody reopens it>
- <a constraint: platform, budget, a library that must or must not be used>

## Checks

The commands that must pass before anything is merged. The tester runs these through `squad heavy`, as separate commands with their own exit codes.

- `<type check command>`
- `<lint command>`
- `<unit test command>`

## Visual check

How to look at the result, and what "correct" looks like. Leave "None" for work with nothing to look at.

- Viewer: `<the command that starts the app, the preview or the component browser, with its port>`
- Sizes and modes: <for example 390 and 1440 px, light and dark>
- Reference: <the design file, the approved page or the existing screen to compare with>
- Rule: <for example "every measured value equals the reference; close is a defect">

## Definition of done

<What must be true for the whole goal, not for one task: the full check run, the visual pass, the docs.>
