# 015 · squad's future versions under the Functional Source License (FSL)
Status: Draft — waiting for approval
Size: S (≤ 2 h)

## Goal
squad stays free to use, but nobody may sell squad, or a product made from it, in competition with
its owner. Each version becomes MIT two years after its release. The owner chose option B (FSL) on 17 Nov 2026.

## Scope
- In: `LICENSE` becomes the official FSL-1.1-MIT text (from github.com/getsentry/fsl.software,
  unchanged except the Notice line); a short "License" section in `README.md` (what is free, what is
  not, when a version becomes MIT, and that versions before this change stay MIT); the SPDX id
  `FSL-1.1-MIT` in `bin/squad` and `install.sh` headers.
- Out: any change to older versions or tags (they stay MIT); a paid licence or a sales page; changes to
  the git history.

## Done when
- [ ] `LICENSE` is the FSL-1.1-MIT template, byte for byte, with only the Notice line filled:
      `Copyright 2026 <licensor name>`.
- [ ] `README.md` has a "License" section: free for any use except a competing product or service;
      each version becomes MIT two years after its release; versions released before <date of this
      change> stay MIT.
- [ ] `bin/squad` and `install.sh` carry `# SPDX-License-Identifier: FSL-1.1-MIT`.
- [ ] CI passes (shellcheck and the smoke tests).

## Plan
- Copy the template; fill the Notice line.
- Add the README section and the two header lines.
- The PR says plainly: the change applies from this commit on; all earlier commits stay MIT.

## Tests
- `diff` of LICENSE against the official template: only the Notice line differs.
- Existing CI.

## Assumptions & open questions
- Open decision for the owner: the licensor name in the Notice line. Recommendation: your legal name
  as it is in the git history ("Valentin C. Hetriuc"); a company name if squad should belong to a company.
- Assumption: nobody else has contributed code to squad, so the owner alone holds the copyright and may
  change the licence (the git history shows only the owner's commits; AI-generated co-authorship lines
  do not make another copyright holder). Not legal advice: a lawyer can confirm.
- Fact: the official FSL text is used unchanged; a modified licence text would lose the FSL's meaning.
