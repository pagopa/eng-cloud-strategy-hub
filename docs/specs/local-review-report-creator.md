# Spec: `local-review-report-creator`

Status: revised design, not implemented. Corrections from counter-validation
are incorporated; unresolved decisions in section 16 block design freeze.
Date: 2026-11-10.
Origin: grill session that produced
`.review/20261110-review-terraform-aws-backup/report.html`.

## Contents

1. [Goal and scope](#1-goal-and-scope)
2. [Decision log](#2-decision-log)
3. [North stars](#3-north-stars)
4. [Three-layer model](#4-three-layer-model)
5. [Report structure](#5-report-structure)
6. [HTML contract](#6-html-contract)
7. [Design system](#7-design-system)
8. [UX features](#8-ux-features)
9. [Mermaid diagrams](#9-mermaid-diagrams)
10. [Bundle layout](#10-bundle-layout)
11. [Skill workflow](#11-skill-workflow)
12. [Checker contract](#12-checker-contract)
13. [Eval pack](#13-eval-pack)
14. [Implementation plan](#14-implementation-plan)
15. [Parked items and open risks](#15-parked-items-and-open-risks)
16. [Counter-validation](#16-counter-validation)

## 1. Goal and scope

Create a local skill that turns review findings into a single-file HTML
report. Every report must have the same structure, behavior, and quality
floor, including when a cheaper model writes it. The model keeps freedom for
case-specific content and stylistic choices inside declared limits.

**In scope**

- Structure and presentation of any technical review: Terraform, code,
  architecture, documents, or configuration.
- A starter template, a component catalog, a style guide, a deterministic
  checker, and an optional diagram-embedding script.
- Italian as the default report language; English labels supported.

**Out of scope**

- Performing the analysis. Analysis stays with the review owners, such as
  `internal-review-code` and `internal-review-high-level`. This skill starts
  from findings that already exist, or collects them from a review just
  completed in the conversation.
- Reclassifying source findings, changing their verdict, or inventing
  evidence, confidence, examples, fixes, or structural proposals.
- Runtime calls to `pbakaus-impeccable` design commands. They are used once,
  during template design.
- Deciding whether `.review/` is ignored by Git.

This revision changes only this specification. It does not authorize skill
implementation, validator or sync changes, paid model runs, report migration,
or Git index changes. The document stays at the explicitly requested path.

## 2. Decision log

| ID | Decision |
|---|---|
| Q1 | Working name: `local-review-report-creator`. Repository path is pending C1; the current validator rejects the original `.github/skills/local-review-report-creator/` path. |
| Q2 | Hybrid model, not a JSON-to-HTML renderer: fixed macro template, model fills and extends it. |
| Q3 | Presentation and structure only; source severity, verdict, confidence, and evidence must be preserved. The severity adapter is pending C2. |
| Q4 | Report skeleton derives from the north stars; see sections 3 and 5. |
| Q5 | Italian by default; English labels through `lang`. The proposed source/chat-language default remains pending C10. |
| Q6 | Use `pbakaus-impeccable` once to design and audit the template; not at report time. |
| Q7 | Adopt the eight north stars in section 3. |
| Q8 | Three layers: invariant, adjustable, free. |
| Q9 | Starter template with `data-*` slots, component catalog, and a read-only stdlib Python checker. Scaffolding and derived-field generation remain pending C3. |
| Q10 | Mandatory, optional, and free sections as in section 5. |
| Q11 | Prefer embedded SVG. A pinned CDN renderer is a degraded fallback; missing embedding is a warning and prevents a fully offline claim. |
| Q12 | Output path: `.review/<YYYYMMDD>-review-<slug>/report.html`. |
| Q13 | UX features a–g in section 8; no search, progress bar, or entrance animations. |
| Q14 | Severity uses a text badge plus a distinct SVG shape; no thick colored border. |
| Q15 | System font stack, fixed role scale, themed browser surfaces, four vetted accents. |
| Q16 | Run `impeccable detect --json` with telemetry disabled as a warning-only check when the binary exists; absence is `not-run`. |
| Q17 | Every finding declares an evidence state. |
| Q18 | Embed SVG from `mmdc` or a controlled browser when available; otherwise keep the pinned CDN. Do not inline the Mermaid library. |

## 3. North stars

These rules are non-negotiable. The checker enforces the testable parts; the
eval rubric covers the rest.

1. **Verdict in 30 seconds.** The header and summary state the outcome,
   counts per severity, and the direction.
2. **Each finding stands alone.** Severity, problem, concrete example, fix,
   and sources, in short and direct sentences.
3. **Recommendations have visible boundaries.** Each has a clear start, a
   closing conclusion, and a before/after comparison when structure or flow
   changes.
4. **Evidence is honest.** Verified fact, conditional risk, correct behavior,
   and missing verification stay distinct. `not-run` never means passed.
5. **Technical review, not conversation.** No colleague framing, reassurance,
   or filler.
6. **Visuals serve content.** Diagrams only for relationships, flows, or
   comparisons.
7. **Progressive simplicity.** Essentials are visible, secondary detail is
   expandable, and nothing is repeated.
8. **Quality floor.** Works offline, prints well, reads on mobile, works with
   a keyboard, and keeps every diagram source. Report text and diagram
   sources must work offline without JavaScript. Fully offline rendered
   diagrams require embedded SVG; a CDN fallback must be reported as degraded.

## 4. Three-layer model

| Layer | Contents | Owner |
|---|---|---|
| Invariant | Page shell, navigation, severity system, evidence states, recommendation frame, before/after component, print and expand behavior, accessibility, diagram fallback, checker markers | Template; never edited by the model |
| Adjustable | Accent from the vetted list, density (`comfortable` or `compact`), section titles, optional sections | Model, through declared attributes |
| Free | Case-specific components: comparison tables, timelines, matrices, extra diagrams, code samples, extra sections | Model, inside free slots and bound by the north stars |

The model must not edit the invariant CSS or JavaScript blocks. It may add
case-specific CSS only inside the `<style data-slot="custom-style">` block,
using the existing tokens.

## 5. Report structure

| Order | Section | Status |
|---|---|---|
| 1 | Header: title, scope, verdict, severity counts, analysis disclaimer | Mandatory |
| 2 | Summary (`Sintesi`) | Mandatory |
| 3 | Recommendations (`Raccomandazioni`) | Optional; only for structural proposals |
| 4 | Free sections | Optional |
| 5 | Findings by severity (`Criticità`) | Mandatory |
| 6 | Notes and limits (`Note e limiti`) | Mandatory when any `note` finding exists |
| 7 | Evidence and limits of the analysis (`Evidenze`) | Mandatory |
| 8 | Order of work (`Ordine degli interventi`) | Optional; required when any `blocker` or `important` exists |

**Severity scale** (fixed):

These are the existing presentation values, not permission to reassess
severity. The supported source-to-presentation mapping is unresolved (C2).
Do not silently map `critical` to `blocker`, or collapse `medium` and `low`;
those transformations may change release meaning or lose distinctions.
Freeze the adapter contract before implementing this part of the template.

| Value | Label (it / en) | Meaning |
|---|---|---|
| `blocker` | Bloccante / Blocker | Documented contract or safety property to fix before release |
| `important` | Importante / Important | Declared property or expected protection to clarify or verify |
| `improvement` | Miglioramento / Improvement | Control or robustness to strengthen |
| `note` | Nota / Note | Behavior or limit to know; explicitly not a bug |

**Evidence states** (fixed):

| Value | Label (it / en) |
|---|---|
| `verified` | Verificato / Verified |
| `reproduced` | Riprodotto con test o mock / Reproduced |
| `documented` | Documentato / Documented |
| `conditional` | Condizionato / Conditional |
| `unverified` | Non verificato / Unverified |

The separation of `conditional` from evidence provenance is pending C15.
Until resolved, retain the source's condition explicitly in the finding
limits. Do not infer `verified` from a severe finding or a proposed test.

**Finding anatomy**: badge row (severity and evidence state), title, problem,
example, fix, limits (optional), sources, optional expandable detail.
A `note` uses `indication` instead of `fix`; its example is optional.
All required parts must contain meaningful text, not template placeholders.
Missing substantive input goes back to the review owner; the formatter must
not fabricate it.

Every finding retains its exact source ID, source severity, and any supplied
confidence. HTML anchors are separate identifiers; source IDs must not be
rewritten to make anchors. Scope source IDs by source review when several
reviews use the same ID. Defects appear only in `findings`; notes appear only
in `notes`. Each finding is counted once across both sections.

**Recommendation anatomy**: header (ID, title, one-sentence proposal), body
(before/after, why, how, examples, expandable detail), footer conclusion
(benefit, cost, and what stays valid today). Each recommendation references
at least one finding through `data-refs`, a space-separated list of finding
anchor IDs. Reuse source proposals; do not perform a new design review.
Before/after is required when the proposal changes structure or flow, not
when a diagram would merely decorate the text.

## 6. HTML contract

The checker relies on these markers. Names are stable API.

```html
<html lang="it" data-report="review" data-template-version="1"
      data-accent="blue" data-density="comfortable">
<header data-slot="header">
  <p data-slot="verdict">…</p>
  <p data-slot="analysis-disclaimer">…</p>
  <ul data-slot="counts">
    <li data-count="blocker">1</li>
    <li data-count="important">3</li>
    <li data-count="improvement">4</li>
    <li data-count="note">3</li>
  </ul>
</header>
<section data-section="summary" id="sintesi">…</section>
<section data-section="recommendations" id="raccomandazioni">
  <article data-recommendation id="r1" data-refs="blocker-1">
    <header>…</header>
    <div data-part="before-after">
      <figure data-diagram data-side="before">…</figure>
      <figure data-diagram data-side="after">…</figure>
    </div>
    <footer data-part="conclusion">…</footer>
  </article>
</section>
<section data-section="custom" id="…">…</section>
<section data-section="findings" id="criticita">
  <article data-finding id="blocker-1"
           data-source-review="review-1" data-source-id="BLOCKER-1"
           data-source-severity="BLOCKER"
           data-severity="blocker" data-evidence="reproduced">
    <p data-part="problem">…</p>
    <p data-part="example">…</p>
    <p data-part="fix">…</p>
    <p data-part="sources">…</p>
  </article>
</section>
<section data-section="notes" id="note">…</section>
<section data-section="evidence" id="evidenze">
  <ul>
    <li data-check id="check-1" data-status="not-run">
      <code data-part="check-command">…</code>
      <span data-part="check-result">Non eseguito: …</span>
    </li>
  </ul>
</section>
<section data-section="actions" id="interventi">…</section>
```

The excerpt shows markers, not a complete valid fixture; its sample counts
do not describe the single example finding. The source severity example is
illustrative, not a resolved adapter contract.

`data-confidence` is optional and must preserve the supplied source value
without inferring a score or converting scales. Display source metadata as
visible text, not only hidden attributes.

Every reported check has a unique anchor, a `data-status` of `passed`,
`failed`, `not-run`, or `blocked`, a non-empty `check-command` naming the
command or review, and a non-empty `check-result`. Missing execution evidence
is `not-run` or `blocked`, never `passed`. Keep existing failed results.
If the source lists no checks, record that absence as `not-run`; this is not
a claim that any command ran. The checker validates structure and allowed
values; source comparison is required to judge whether a status is truthful.

Diagram figure:

```html
<figure data-diagram>
  <div class="diagram" role="img" aria-label="…"><!-- optional embedded SVG --></div>
  <figcaption>…</figcaption>
  <details class="diagram-source"><summary>Sorgente Mermaid</summary>
    <pre class="mermaid-source">flowchart TB
    accTitle: …
    accDescr: …
    …</pre>
  </details>
</figure>
```

## 7. Design system

Source rules: `pbakaus-impeccable` `reference/craft-floor.md` and
`reference/typeset.md`, plus the lessons from the Terraform report.

**Tokens** (named by purpose): `--ink`, `--ink-muted`, `--surface`,
`--surface-sunken`, `--line`, `--accent`, `--accent-soft`, `--sev-blocker`,
`--sev-important`, `--sev-improvement`, `--sev-note`, each severity with a
`-soft` variant, `--radius-control`, `--radius-panel` (12–16px), `--measure`
(70ch), and a spacing scale.

**Typography**

- One system sans stack; no web fonts.
- Monospace only for code, identifiers, and data.
- Fixed role scale: display, h2, h3, h4, body (≥1rem), label, meta, data.
- `font-variant-numeric: tabular-nums` for counts and tables.
- `text-wrap: balance` for headings and `text-wrap: pretty` for body.
- Body measure 65–75ch; more space above a heading than below it.

**Accents** (adjustable): `blue`, `green`, `violet`, `graphite`. Implementation
must verify normal text contrast of at least 4.5:1 on light and dark surfaces
before the palette is called vetted.

**Severity display**: text badge plus inline SVG shape. Octagon for
`blocker`, triangle for `important`, circle for `improvement`, info mark for
`note`. Meaning must survive grayscale print and color-blind viewing.

**Browser surfaces**: themed text selection, focus ring, scrollbars, and link
underline offset.

**Themes**: light by default; dark through `prefers-color-scheme`. Both must
pass contrast checks; no palette has been implemented or measured yet.

**Refused patterns** (checker or `impeccable detect` flag them):

- Colored `border-left` or `border-right` wider than 1px on cards or callouts.
- Eyebrow labels above headings.
- Emoji or Unicode glyphs as icons.
- Card grids as page structure; nested cards.
- Hero-metric blocks; gradient text; decorative blur or glass.
- Monospace used as decoration.
- Same entrance animation on every section.

## 8. UX features

| ID | Feature | Behavior |
|---|---|---|
| a | Severity filters | Toggle chips with counts; `aria-pressed`; hidden findings keep anchors working; filter state never affects print |
| b | Finding permalinks | Copy-link button per finding; `:target` highlight |
| c | Copy as issue | Copies title, source ID/severity, confidence when supplied, evidence state, problem, example, fix or indication, and sources. Visible only when `navigator.clipboard` exists; explicit inline failure status if copying is denied |
| d | Before/after | Side by side at ≥900px; tabs (`role="tablist"`) below; both panes print side by side |
| e | Navigation | Sticky sidebar with active-section state on desktop; compact wrap on mobile; skip link |
| f | Expand/collapse all | One button for every non-source `<details>`; print expands all and restores the previous state |
| g | Dark mode | Automatic through `prefers-color-scheme` |

All features use progressive enhancement: the report stays complete and
readable without JavaScript. Respect `prefers-reduced-motion`.

## 9. Mermaid diagrams

- Every figure keeps its Mermaid source with `accTitle` and `accDescr`.
- Sources follow `internal-mermaid` theme-neutral rules: no `style`,
  `classDef`, `linkStyle`, `theme`, or init directives on text boxes.
- Runtime fallback target: Mermaid `11.17.2` from jsDelivr, pinned version with SRI,
  `securityLevel: 'strict'`, `htmlLabels: false`, `parse` before `render`,
  inline error message, and source opened on failure.
- Before template release, verify the exact distributable and browser-loading
  method. Compute SRI from the bytes used and record the URL, version, hash,
  and renderer version in `references/diagrams.md`. A successful CDN response
  alone does not establish API compatibility or integrity of transitive
  imports. The artifact and SRI are not yet validated.
- `scripts/embed_diagrams.py` writes SVG into each `.diagram` and scopes SVG
  IDs to avoid duplicates. SVG input comes from the first available renderer:
  1. `mmdc`, when installed;
  2. a controlled browser, such as the integrated browser tool or Playwright,
     following the documented procedure in `references/diagrams.md`.
- When every diagram is embedded, the page loads no external script.
- The checker reports non-embedded diagrams as a warning. Test with network
  disabled and an empty cache; a warm-cache render is not offline evidence.
- The origin report's embedded SVG demonstrates the output shape, not the
  correctness or availability of the future embedding script.

## 10. Bundle layout

```text
<approved-bundle-root>/          # Location and name pending C1
  SKILL.md                     # Trigger, workflow, completion criteria
  agents/openai.yaml           # Host projection
  assets/template.html         # Starter template with all invariants
  references/
    authoring.md               # North stars, tone, good/bad examples
    components.md              # Copy-ready component snippets
    style-guide.md             # Tokens, accents, refused patterns
    diagrams.md                # Mermaid rules and embedding procedure
  scripts/
    check_report.py            # Deterministic checker, stdlib only
    embed_diagrams.py          # SVG embedding and ID scoping
  tests/
    test_check_report.py
    test_embed_diagrams.py
    fixtures/
      valid-report.html
      defective-*.html         # One defect per fixture
    evaluation/
      evals.json
```

`SKILL.md` stays within the always-loaded budget of the skill-creator
reference: trigger-first description of about 1,024 characters or less, and
the body within about 500 lines. Every reference is linked from `SKILL.md`.
These are review budgets, not universal host limits. A `scaffold_report.py`
and its native tests would be added only if C3 is accepted.

Draft description:

> Use when a technical review is finished and its findings must be published
> as a single-file HTML report under `.review/`. Covers severity-ordered
> findings, bounded recommendations with before/after Mermaid diagrams,
> evidence limits, and a fixed, checked layout. Not for performing the
> review itself; use `/internal-review-code` or `/internal-review-high-level`
> first.

## 11. Skill workflow

1. **Collect input.** Confirm the findings source, scope, language, and
   output slug. A missing review is not an empty review: route missing
   analysis to its owner. An explicit zero-findings result remains a valid
   report with zero counts and the source verdict.
2. **Preserve and adapt.** Keep source IDs, severity, verdict, confidence,
   evidence, conditions, and substantive fields. Use only a frozen adapter,
   once C2 is resolved. Keep source-marked notes separate from defects and
   reuse existing structural proposals. Stop for missing input rather than
   inventing it.
3. **Copy the template** to `.review/<YYYYMMDD>-review-<slug>/report.html`.
   Do not overwrite an existing report without authorization. The scaffolding
   alternative is pending C3.
4. **Fill slots** with components from `references/components.md`. Choose an
   accent and density. Add free sections only when the north stars justify
   them.
5. **Write diagrams** following `references/diagrams.md`. Embed SVG when a
   renderer is available.
6. **Check**:

   ```bash
   python3 <bundle>/scripts/check_report.py <report.html> --format text
   IMPECCABLE_NO_TELEMETRY=1 \
     <impeccable>/scripts/impeccable detect --json <report.html>
   ```

7. **Fix** every checker error. Report warnings that remain. The optional
   detector is warning-only; its absence is `not-run`, not a pass.
8. **Report back**: path, counts, warnings, evidence gaps, and diagram
   embedding/offline status. Do not stage, publish, or transmit the report.

**Completion criteria**: the checker exits 0; every warning is resolved or
reported; the report opens in a browser without console errors. Browser or
offline checks that cannot run remain explicit validation gaps, not passes.
Report-generation checks are distinct from the original review's checks;
formatting a report must not change the source review verdict.

## 12. Checker contract

`check_report.py` uses only the Python standard library. Exit codes: `0`
clean, `1` errors, `2` usage error. Output formats: `text` and `json`.
Warnings alone exit `0`; that means structurally valid with possible
warnings, not fully validated. The checker is read-only. A `--fix` mode is
not part of the accepted contract; it remains a C3 proposal.

Use `html.parser` with explicit contract checks, including a nesting stack
that handles HTML void elements. It is not a full HTML5 conformance validator
or a browser accessibility checker. JSON diagnostics need stable rule IDs,
severity, and finding/element locations so baseline deltas are comparable.

**Errors**

- Missing mandatory section, or a required optional section is missing.
- HTML nesting is unbalanced, or IDs are duplicated.
- Fragment links point to a missing ID; relative file links point to a missing
  file.
- A finding has an invalid or missing `data-severity` or `data-evidence`.
- A finding lacks non-empty `problem` or `sources`. A non-note finding lacks
  non-empty `example` or `fix`. A note lacks non-empty `indication`; it need
  not contain `fix` or `example`.
- A finding lacks source review, source ID, or source severity; a source
  review/ID pair is duplicated; a note is misplaced or counted twice.
- Header counts do not match the findings.
- A recommendation lacks a header, a non-empty `conclusion` footer, or
  non-empty `data-refs`; any reference fails to resolve to a finding.
- A `before-after` block lacks exactly one `before` and one `after` figure.
- A diagram lacks a Mermaid source, `accTitle`, or `accDescr`.
- A reported check lacks an allowed `data-status`, a non-empty
  `check-command`, or a non-empty `check-result`; the evidence section contains
  no reported checks.
- Unknown `data-accent`, `data-density`, or `data-template-version` value.
- An invariant block hash differs from the template, for the CSS, script, and
  severity icon blocks.

Invariant blocks must each occur exactly once and use template-owned markers.
Normalize only CRLF/CR to LF before hashing; do not discard whitespace inside
CSS, JavaScript, or SVG. Compare against the bundled template version, not a
hash declared by the report. An older version is accepted only when its
template and validation contract are shipped and tested. Hash equality does
not prove that custom CSS cannot override invariant behavior; evaluate that
separately.

**Warnings**

- A diagram is not embedded as SVG.
- The report loads an external script while all diagrams are embedded.
- Refused-pattern heuristics: colored side borders wider than 1px, emoji in
  headings or badges, or eyebrow elements above headings.
- Colleague-framing phrases, such as `caro collega`, `ai colleghi`, or
  `da portare alla discussione`. Do not flag the bare word `collega`;
  `il modulo collega X a Y` is legitimate technical prose.
- Prose paragraph longer than 120 words.

Semantic claims, source fidelity, secret disclosure, CSS overrides, actual
contrast, keyboard behavior, and printing need source or browser review.
Do not describe the stdlib checker as enforcing those guarantees.

## 13. Eval pack

Path: `tests/evaluation/evals.json`, schema `skill-eval-pack/v1`. Validate
with the skill-creator checker.

**Requirements**

| ID | Requirement | Source heading |
|---|---|---|
| R-structure | Mandatory sections and HTML contract present | §5, §6 |
| R-severity | Source severity/verdict/confidence preserved; counts match; adapter acceptance blocked on C2 | §5, §6 |
| R-evidence | Findings retain evidence and conditions; checks have explicit statuses; no `not-run` as passed | §3, §5, §6 |
| R-recommendation | Source-backed recommendations with finding references, conclusion, and before/after when structural | §3, §5, §6 |
| R-invariants | Invariant blocks unchanged and versioned; adjustable values valid | §4, §6, §12 |
| R-diagrams | Sources kept, accessible, theme-neutral; embedding attempted; offline claims tested | §9 |
| R-tone | Technical, direct, no colleague framing or repetition | §3 |
| R-freedom | Case-specific components allowed inside free slots | §4 |
| R-scope | No invented findings or reassessment; missing review routed to owner; explicit zero findings supported | §1, §11 |

**Cases**

- Deterministic, one defective fixture each: missing conclusion, count
  mismatch, invalid severity, missing evidence state, duplicate ID, diagram
  without source, edited invariant CSS, unknown accent, missing check status,
  invalid check status, empty check result, unresolved recommendation
  reference, missing source ID, duplicate source ID within one review,
  unknown template version, missing or duplicated invariant block.
- Executable: embedding script scopes IDs and preserves sources.
- Positive regressions: note with `indication` and no `fix` passes; zero
  findings passes with an explicit source verdict; technical use of `collega`
  is not warned; identical source IDs from distinct reviews remain traceable;
  literal HTML in source evidence is escaped, not executed.
- Browser cases: network disabled and empty cache, JavaScript disabled,
  clipboard denial, filtered-target navigation, keyboard tabs, print state
  restoration, mobile layout, and dark-mode contrast.
- Judgment, with anchored rubrics: source fidelity, tone and simplicity;
  recommendations traceable to source findings; justified
  use of a free component.
- Cross-model consistency: the same findings rendered by a cheaper and a
  stronger model both pass the checker and keep identical invariant hashes.
  Compare source content and metadata as well as hashes. Runs need explicit
  approval; absent runs are `not-run`. C7 decides whether these runs block
  release. Until measured, cheaper-model reliability is an unverified goal.

**Trigger queries**: positive (`genera il report HTML della review`, `publish
these findings as a report`) and negative (`fai la review di questo modulo`,
which belongs to the review owners; `crea una landing page`).

## 14. Implementation plan

Resolve the design-freeze decisions in section 16 before implementing.
Steps below describe future work, not completed or authorized work. Write
failing native tests for each executable seam before implementing it.

| Step | Work | Complete when |
|---|---|---|
| 1 | Build `assets/template.html` from the Terraform report, applying §5–§8 | Template renders with sample content; every feature works |
| 2 | Use the `pbakaus-impeccable` critique and audit workflows; run the detector with telemetry disabled | Findings fixed or recorded as accepted; do not assume critique/audit are CLI subcommands |
| 3 | Write `check_report.py` and its tests, failing first on defective fixtures | Unit tests pass; valid fixture is clean |
| 4 | Write `embed_diagrams.py` after failing tests; verify the pinned renderer artifact and SRI | Tests pass; embedded page renders with network disabled and empty cache, with no external script loads |
| 5 | Write `references/*` and `SKILL.md`; run the frontmatter checker | Checker passes; all references linked |
| 6 | Write `evals.json`; run the eval-pack checker | Checker passes |
| 7 | Generate a separate smoke-test report from the Terraform findings; preserve the origin report | Checker exits 0; source fidelity and mobile, desktop, print, keyboard, and dark-mode checks pass |
| 8 | Validate the chosen bundle path, host discovery, inventory requirements, and sync scope; run targeted checks before global validation | Bundle checks pass; no new global diagnostics attributable to the task; baseline failures remain explicit |
| 9 | Resolve C7; perform cross-model runs only with explicit approval | If run, both outputs pass with source fidelity and identical invariant hashes; otherwise evidence remains `not-run` |

Validation commands (replace `<bundle>` and `<skill-name>` only after C1 is
resolved; creator validators are maintainer tools, not runtime dependencies
of the report skill):

```bash
python3 ~/.agents/skills/internal-skill-creator/scripts/check_skill_frontmatter.py \
  <bundle>/SKILL.md
python3 ~/.agents/skills/internal-skill-creator/scripts/check_eval_pack.py \
  <bundle>/tests/evaluation/evals.json \
  --bundle-root <bundle> \
  --skill-name <skill-name> --format compact
python3 -m unittest discover -s <bundle>/tests
bash .github/scripts/validate-copilot-customizations.sh --scope root --mode strict
pre-commit run --files <explicit-task-files>
```

The previous counter-validation observed 27 errors and 3 warnings in strict
repository validation. Capture a fresh baseline at implementation start,
retain diagnostics, and compare after the change; the count alone cannot
prove no regression. Do not waive new bundle failures as baseline failures.
The current validator requires skill entries in `AGENTS.md`, while the root
policy discourages inventory there. Resolve this owner conflict before
changing either surface; do not automatically add an inventory to bypass it.
Do not repair unrelated policy, workflow, or token-risk failures in this task.

## 15. Parked items and open risks

- **Parked (C5):** decide whether `.review/` is tracked. The Terraform report
  is already tracked; adding an ignore rule alone would not untrack it.
  No index or history change is authorized by this specification.
- **Open (C1):** the proposed repository path fails current strict naming.
  Do not assume a `local-` prefix prevents bootstrap distribution.
- **Open (C2, C3, C7, C10, C15):** adapter semantics, generation ownership,
  release evidence, language default, and evidence axes need decisions.
- **Risk:** template versions require a bundled validation contract; there
  is no automatic one-version hash grace period.
- **Risk:** a CDN fallback is not fully offline. Embedding depends on an
  available renderer; the checker warning keeps the gap visible.
- **Risk:** `impeccable detect` is an external binary. It stays warning-only
  and its absence is reported, not treated as a pass.
- **Risk:** source material and SVG may contain confidential data or active
  markup. Keep generation local, escape source text, and review rendered
  output and SVG handling before any publication. A secret-like-value
  heuristic is not a confidentiality guarantee and is not added here.
- **Risk:** the current `AGENTS.local.md` references `make token-risks` and
  `.github/INVENTORY.md`, which do not exist. Resolve outside this work.

## 16. Counter-validation

Date: 2026-11-10. Method: inspect the specification against repository
validators, source review contracts, the origin HTML, and the local
toolchain. The findings below retain their original IDs for traceability.
Section 16.3 records what this revision incorporates and what still needs
a decision. No unavailable answer from the previous questionnaire counts as
approval.

### 16.1 Decisions that hold

| Decision | Evidence |
|---|---|
| Q2 hybrid model | The Terraform report mixes fixed structure and case-specific sections (`confronto`, `verifiche`); this supports the pattern, not the reliability of a future template. |
| Q11, Q18 SVG embedding | The Terraform report contains embedded SVG with scoped IDs (`data-id-scoped`). This establishes an example output, not a tested embedding script. |
| Q16 `impeccable detect --json` | The binary ships in the bundle at `pbakaus-impeccable/scripts/impeccable` and supports `detect --json`. |
| §10 budgets | `cache-and-token-efficiency.md` treats 1,024 characters and 500 lines as practical review budgets. |
| §13 schema | Field names match `eval-packs.md` schema v1. |
| §12 stdlib checker | Python 3.14 was available during inspection. `html.parser` can support explicit marker and nesting checks, but does not validate HTML5, accessibility, or semantic truth by itself. |
| §15 `AGENTS.local.md` risk | Confirmed: `.github/INVENTORY.md` and `detect_token_risks.py` do not exist. |

### 16.2 Findings

These findings describe the pre-revision specification and the inspection
baseline. Section 16.3, not the historical wording below, defines their
current disposition.

| ID | Severity | Affects | Finding |
|---|---|---|---|
| C1 | Blocker | Q1, §10, §15 | The strict validator accepts only `internal-*` and `tech-ai-*` skill directories (`validate_repo_local_skill_naming`). The bootstrap includes skill bundles unless explicitly excluded; a `local-` prefix is not an exclusion. No `.bootstrap-ignore` existed during inspection. The original bundle path fails strict validation and remains eligible for distribution. |
| C2 | Blocker | Q3, §5, §11 step 2 | Step 2 assigns severity, which is analysis and contradicts Q3. The spec adds a fourth severity scale. `internal-review-code` emits `BLOCKER`, `IMPORTANT`, `SUGGESTION` and a verdict. `internal-review-high-level` emits `critical`, `high`, `medium`, `low` plus confidence. No mapping is defined, and confidence has no slot. |
| C3 | Important | Q9, §1 goal | The origin report is 79,438 bytes; the future template size is unknown. Reproducing entire reports risks excess output tokens and invariant drift. Counts and navigation are derivable but have no generation owner. |
| C4 | Important | §11, §14 step 8 | The strict validator already fails on the baseline with 27 errors and 3 warnings outside this scope. "Commands pass" is unreachable. `validate_agents_inventory` also requires an `AGENTS.md` entry for every `SKILL.md`, which §14 omits. |
| C5 | Important | §1, §15 | `.review/20261110-review-terraform-aws-backup/report.html` is tracked in commit `209a499` on `feat/aws_backup_module`, under an unrelated message. The parked `.gitignore` decision already has an effect. Reports can carry internal findings and secret-like values. |
| C6 | Important | §3 star 4, §6, §12 | The `Evidenze` section has no HTML contract. `not-run` has no marker, so R-evidence cannot be checked. |
| C7 | Important | §1, §14 step 9 | Cheaper-model consistency is the primary goal, but the cross-model run is optional. Without it the goal stays unverified. |
| C8 | Minor | §9 | The origin report references Mermaid 10.9.3 without SRI. The CDN resolved 11.x to 11.17.2 during inspection; that response did not validate the artifact or runtime API. `mmdc` was not installed locally. |
| C9 | Minor | §12 | The tone heuristic `collega` matches the Italian verb (`il modulo collega X a Y`). |
| C10 | Minor | Q5 | `internal-review-high-level` follows the chat language. A fixed Italian default diverges from the sibling convention. |
| C11 | Minor | §5, §6 | Recommendations do not reference findings. Source IDs have no dedicated field; HTML anchors alone cannot preserve source identity or disambiguate several reviews. |
| C12 | Minor | Q16 | `impeccable` telemetry is on by default. It states that no code is sent, but the run command does not disable it. |
| C13 | Minor | Document location | `AGENTS.local.md` keeps repo-local planning and analysis outside `docs/`. `docs/specs/` is new and untracked. |
| C14 | Minor | §6 | `data-template-version` appears only in §15, not in the HTML contract. |
| C15 | Minor | §5 evidence states | `conditional` describes when a risk applies, not how it is known. It mixes two axes with `verified`, `reproduced`, `documented`, and `unverified`. |

### 16.3 Disposition and open decisions

| ID | Current disposition | State |
|---|---|---|
| C1 | Recommended: `internal-review-report-creator` under `.github/skills/`, with distribution understood. Alternatives: retain `local-` with tested validator/sync changes, or install outside the repository. No path is frozen; §§2, 10, 14 use this gate. | Open; blocks bundle creation |
| C2 | §11 no longer assigns severity or evidence; §§5–6 preserve source metadata and verdict. Decide between native source scales and an owner-approved presentation adapter. The earlier automatic `critical`→`blocker`, `high`→`important`, and `medium`/`low` collapse is withdrawn: severity alone does not determine release policy. | Preservation incorporated; scale choice open |
| C3 | The baseline checker remains read-only. Proposed: a scaffold command copies invariant blocks, then an explicit generation step derives counts/navigation from slots. Decide generation ownership and CLI before adding scripts or `--fix`. Hash normalization now preserves meaningful whitespace (§12). | Generation choice open |
| C4 | §14 requires a fresh diagnostic baseline and no new task-attributable failures. The validator's inventory demand conflicts with root policy; resolve that contract before adding a skill inventory. Global baseline failures are not repaired here. | Delta criterion incorporated; inventory conflict open |
| C5 | §15 records that the report is already tracked and leaves Git policy parked. No ignore/index/history change or secret-scanner promise is introduced. Review confidentiality before any publication. | Parked; separate authorization required |
| C6 | §§6, 12, 13 define check markers, four statuses, non-empty command/result fields, defective fixtures, and the boundary between structural and truthful evidence. | Incorporated |
| C7 | §13 marks cheaper-model reliability unverified without actual runs. Decide whether cross-model evidence gates release; approval to run a model is separate from choosing that criterion. | Open; evidence `not-run` |
| C8 | §9 targets Mermaid 11.17.2, requires exact artifact/API verification and SRI, and records the browser fallback. §14 adds a network-disabled, empty-cache test. No checksum or renderer test is claimed complete. | Requirement incorporated; implementation checks `not-run` |
| C9 | §12 matches framing phrases rather than bare `collega`; §13 includes the technical-verb regression case. | Incorporated |
| C10 | Preserve the previously declared Italian default. Proposed alternative: explicit language override, then source/chat language, with `it` only when ambiguous. | Open; Q5 unchanged |
| C11 | §§5–6 retain exact source review/ID/severity and optional confidence separately from anchors. Recommendations use validated `data-refs`. Lowercasing source IDs is not required. | Incorporated |
| C12 | §11 runs the detector with `IMPECCABLE_NO_TELEMETRY=1`; §§11–12 distinguish absence from a pass. | Incorporated |
| C13 | The current request explicitly targets this specification. Keep its path; no relocation or new planning artifact. Future bundle guidance must be self-contained. | Resolved for this revision |
| C14 | §§6, 12, 13 define the version marker, version validation, and fixtures. Only bundled, tested template contracts are accepted. | Incorporated |
| C15 | Preserve the current vocabulary pending an evidence-axis decision. Proposed: provenance values without `conditional`, plus explicit condition text in a separate field. Do not silently convert conditional risk into verified fact. | Open; conditions preserved |

### 16.4 Design-freeze gate

Before implementation, resolve C1 (name, location, distribution), C2 (source
severity projection), C3 (generation ownership), C4 (inventory contract),
C7 (release evidence), C10 (language default), and C15 (evidence axes).
C5 stays outside skill implementation unless separately authorized.

The earlier audit also overstated several guarantees. This revision
corrects them: an embedded example does not validate an embedding tool;
`html.parser` does not validate semantics; an unimplemented palette has not
passed contrast checks; a CDN response does not validate a renderer; and
matching invariant hashes does not prove source fidelity or safe custom CSS.
The evaluation and implementation sections now expose those evidence gaps.
