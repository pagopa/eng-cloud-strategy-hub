# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Single-file static HTML with inline CSS and JS. No build step, no web fonts, no external runtime except an optional pinned Mermaid CDN fallback (spec §3, §10).

## Users

- Developer who fixes findings one at a time: opens the report next to the code, needs the action, the diff, and the source location for each finding.
- Lead or owner who decides: needs the verdict, severity counts, and the order of work within 30 seconds.
- Reviewer who checks honesty: needs evidence state, source ID, source severity, confidence, checks run, and what was not run.

## Product Purpose

`local-review-report-creator` turns findings of an existing technical review (Terraform, code, architecture, documents, configuration) into one self-contained HTML report. Every report has the same structure, behavior, and quality floor, including when a cheaper model writes it. Success: the verdict is clear in 30 seconds, and each finding can be acted on alone.

## Positioning

A formatter, not an analyst: it never reclassifies severity, invents evidence, or adds recommendations. Its value is a fixed, checkable contract (data-* markers read by a deterministic checker) that makes reports comparable across reviews and models.

## Operating Context

Reports live at `.review/<YYYYMMDD>-review-<slug>/report.html`, opened locally in a browser, shared as a file, attached to PRs or tickets, or printed to PDF. Italian by default, English labels supported.

## Capabilities and Constraints

- Section order (spec §5): header with verdict and tally, Sintesi, Criticità index, Raccomandazioni, free sections, Dettaglio delle criticità, Note e limiti, Evidenze, Ordine degli interventi.
- Fixed severity scale: blocker, important, improvement, note; each with a text label and a distinct SVG shape that survives grayscale.
- Fixed evidence states: verified, reproduced, documented, conditional, unverified. `not-run` never means passed.
- Must work offline and without JavaScript; prints well; reads on mobile; keyboard accessible; keeps every Mermaid source.
- Open (user decision for this exploration): the §6 HTML contract may change; the spec will be aligned afterwards.

## Evidence on Hand

Mock data only: a fictional Terraform S3 module review (`docs/specs/local-review-report-creator/templates/c-tabella.html`). No real customer data, metrics, or claims.

## Product Principles

1. Verdict before explanation: show what to do before why.
2. Each finding stands alone: problem with impact, example, fix, benefit, sources.
3. Evidence is honest: verified, conditional, and missing verification stay visibly distinct.
4. Technical review, not conversation: no reassurance or filler.
5. Visuals serve content: diagrams only for flows, relationships, comparisons.

## Accessibility & Inclusion

WCAG AA contrast for text (4.5:1), meaning never carried by color alone, keyboard navigation, `prefers-reduced-motion` respected.
