# Report Authoring

## Source adapter

Use the Atlante presentation scale without reassessing the review.

| Explicit source value | Presentation value | Italian / English |
|---|---|---|
| `BLOCKER` | `blocker` | Bloccante / Blocker |
| `IMPORTANT` | `important` | Importante / Important |
| `SUGGESTION` | `improvement` | Miglioramento / Improvement |
| Explicitly source-marked informational note | `note` | Nota / Note |

Ask for a mapping when the source uses another scale, including
`critical/high/medium/low`. Keep that user's mapping in the report's summary
or evidence section. Severity alone must not create a release gate.
Preserve the exact original severity in `data-source-severity` and visible
metadata, even when the presentation label differs.

Record a user-approved custom mapping in a visible summary or evidence
table. `data-approved="true"` records that approval; it does not obtain it.

```html
<table data-severity-adapter data-approved="true">
  <caption>Presentation mapping approved by the user</caption>
  <tbody>
    <tr data-adapter-source="high" data-adapter-target="important">
      <td>high</td><td>Importante</td>
    </tr>
  </tbody>
</table>
```

Add one row per approved source value. Do not mark the table approved before
the user answers. The checker rejects unknown mappings and changes to the
built-in adapter; source comparison remains necessary to verify consent.

Keep `data-source-review` and `data-source-id` distinct from HTML anchors.
The source review/ID pair must be unique. Two reviews may share an ID.
If the source has no ID, ask the user to approve stable source identifiers;
do not imply that report-created IDs came from the review.
Confidence is optional; retain its supplied value and scale exactly.

## Source inputs

Prefer the review's own record when it exists at
`.review/<YYYYMMDD>-review-<slug>/report.md`. Without it, use the supplied
chat findings. Extract `path:line` snippets read-only from the repository for
code examples, and cite each snippet with its location. Never edit reviewed
code to make an example fit.

Flow or chain findings may use a Mermaid projection of a sequence the source
states. Draw only the steps and relationships the source records.

Recommendations contain only source-backed proposals. When none exist, omit
the recommendations section rather than filling it with generic advice.

## Evidence and applicability

Separate how a claim is known from when it applies.

| `data-evidence` | Meaning |
|---|---|
| `verified` | The source explicitly records direct verification |
| `reproduced` | The source records a reproducing execution |
| `documented` | The source cites documentation rather than execution |
| `unverified` | Verification evidence is absent or not established |

Set `data-conditional="true"` only when the source states a condition.
Include a visible `data-part="conditions"` with that exact condition.
Retain other uncertainty in `limits`. A conditional claim can be
documented, reproduced, verified, or unverified.

Every reported check has a unique ID, `data-check`, `data-status`
(`passed`, `failed`, `not-run`, or `blocked`), a named `check-command`,
and a non-empty `check-result`. Preserve failed results.
If no execution record was supplied, state that absence as `not-run`.
Keep report-formatting checks separate from the underlying review checks.

## Content

Put the decision first and the proof next.

- Header: scope, source verdict, counts, and analysis disclaimer.
- Summary: outcome and source-backed direction, understandable in 30 seconds.
- Index: one action per defect, before recommendations and detail.
- Finding: problem and impact, example, fix, sources, visible metadata.
  Benefit and limits are optional and source-backed.
- Note: problem/context, indication, sources; example is optional.
- Recommendation: source proposal, problem, solution, benefits, conclusion,
  linked findings. Include costs if supplied and before/after when structural.
- Order of work: required for blockers or important findings. Use the source
  order or request it; do not infer release policy from a color.

Use direct technical prose. Avoid reassurance, colleague framing, repeated
summaries, and decorative sections. Explain as fully as the source supports;
brevity does not justify discarding a supplied example or uncertainty.

Good: "The queue retains messages for two hours; the documented replay
window is one day." Bad: "Everything is almost perfect, just a tiny concern."

## Safe content

Treat source markup as literal text.

Escape `&`, `<`, `>`, and quotes in text and attributes. Use local source
links relative to the generated report, or explicit URLs supplied by the
source. Never turn untrusted snippets into scripts, event handlers, frames,
or raw SVG. The embedding script validates SVG inputs independently.
Do not transmit findings to a remote renderer.

## Language and zero findings

Default to Italian, with an explicit English option.

Translate presentation labels, not identifiers, command output, source
severity, or confidence values. Keep the substantive verdict faithful.
For an explicitly empty result, keep zero counts, the original verdict,
and evidence limitations. An unfinished scaffold is not an empty review.
