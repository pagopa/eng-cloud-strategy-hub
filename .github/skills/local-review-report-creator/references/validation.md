# Bundle Validation

## Maintainer commands

Run the native checks before host-wide checks.

```sh
python3 -m unittest discover -s <bundle>/tests
python3 <creator>/scripts/check_skill_frontmatter.py <bundle>/SKILL.md
python3 <creator>/scripts/check_eval_pack.py <bundle>/tests/evaluation/evals.json \
  --bundle-root <bundle> --skill-name local-review-report-creator --format compact
```

`<creator>` is the installed `internal-skill-creator` bundle, not a report
runtime dependency. All report scripts use only Python's standard library.
Run `python3 -m unittest discover -s .github/scripts/tests` in the owning
repository to verify its exact local naming and bootstrap exception.

## Structural coverage

`check_report.py` checks markers, required sections and order, source
identity/metadata, evidence and condition fields, required finding parts,
note placement, counts, index coverage/actions, recommendation references,
before/after pairs, diagram sources, check statuses, links, nesting,
active-content patterns, adjustable values, and invariant hashes.
Diagnostics contain stable `rule`, `severity`, `message`, and `location`.

Errors include `empty-recommendations`, a recommendations section with no
recommendation. Warnings cover long paragraphs (`long-prose`) and
conversational framing (`tone`). A structural pass is not proof of truthful evidence, safe custom
CSS, confidentiality, source fidelity, keyboard accessibility, or printing.
The native suite exercises defective mutations from
`tests/fixtures/defects.json`; generated cases remain separate from observed
model-run results.

## Browser acceptance matrix

Use synthetic source material for browser checks.

| Case | Expected observation |
|---|---|
| Desktop | Left rail, right tally, register before recommendation/details |
| Mobile, 390px | No page overflow; horizontal navigation; stacked comparisons |
| OS dark | Light Atlas surfaces and readable contrast |
| Filters | Counts match; index and details hide together; reset works |
| Hidden target | Permalink reveals filtered finding, including unchanged hash |
| Nested target | Parent finding revealed and enclosing details opened |
| Clipboard allowed | Issue includes complete parts/metadata; code omits removals/gutter |
| Clipboard denied | Explicit inline denial; no unhandled rejection |
| No clipboard API | Copy controls stay hidden |
| Print | Filtered findings and disclosures visible; screen state restored |
| JS disabled | Review text and diagram sources remain accessible |
| Offline, empty cache | Embedded diagrams render with no external requests |
| CDN unavailable | Accessible error plus visible source, no false offline claim |
| Pinned CDN | Actual Mermaid parse/render API works with SRI |
| Keyboard | Skip link, visible focus, filters, links, disclosures reachable |
| Reduced motion | No target flash or smooth scrolling |

Check source fidelity against every supplied finding, including optional
details and code. Check custom styles and actual contrast independently.

## Evidence states and discovery

Report observed checks only.

Cross-model effectiveness, trigger accuracy, subjective design acceptance,
and isolated activation are not established by unit tests. The eval pack
specifies these cases with anchored rubrics; model runs require separate
approval. A new chat may be necessary for host discovery of a new skill.
This bundle is local to the repository and excluded from bootstrap; its
presence does not authorize installation in the user's global skill folder.
