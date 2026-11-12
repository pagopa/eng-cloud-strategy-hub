# Review report template proposals

Three simple proposals for `assets/template.html` of the skill specified in
[local-review-report-creator.md](../../local-review-report-creator.md).
All three use the same mock data, the same visual base (system font, light
and dark themes, severity shapes), and the §6 HTML contract. They differ only
in how the reader moves through the report.

| Proposal | Layout | Best for | Image |
|---|---|---|---|
| [A · Documento](a-documento.html) | One centered column; sticky section bar at the top | Short reports, reading top to bottom | [desktop](images/a-documento-desktop.png) · [mobile](images/a-documento-mobile.png) |
| [B · Indice laterale](b-indice.html) | Left index with sections and findings; content on the right | Long reports, jumping between findings | [desktop](images/b-indice-desktop.png) · [mobile](images/b-indice-mobile.png) |
| [C · Tabella e dettaglio](c-tabella.html) **(selected)** | Counts beside the title; finding table, then one detail block per finding | Many findings, triage at a glance | [desktop](images/c-tabella-desktop.png) · [mobile](images/c-tabella-mobile.png) |

Dark-mode images (A and B only): `images/a-documento-desktop-dark.png`, `images/b-indice-desktop-dark.png`.

## Proposal C, iteration 2

- Warm palette: paper surface and terracotta accent. It uses a
  new `data-accent="terracotta"` value; spec §7 lists only four accents and
  must add it if C is adopted.
- Each finding is a labelled grid (Problema, Esempio, Correzione, Limiti,
  Fonti). Parts can hold supporting visuals: a code diff, a flow diagram
  with the failing step highlighted, a timeline, a comparison table, or a
  calculation. Every diagram keeps its Mermaid source.
- Images: [blocker with flow and diff](images/c-tabella-finding-blocker.png),
  [timeline](images/c-tabella-finding-timeline.png),
  [comparison table](images/c-tabella-finding-table.png),
  [mobile finding](images/c-tabella-finding-mobile.png).

## Proposal C, iteration 3

- Light theme only, also when the OS uses dark mode. Spec §8 feature g
  (automatic dark mode) must change if C is adopted.
- Header tally: total points to review, a severity bar, and per-severity
  counts that link to the first finding of each severity. Notes are counted
  separately. On mobile the tally comes first.
- Layout review by Grok 4.7: applied lighter code diffs with a marker
  gutter, a sentence-case label gutter, no nested cards in recommendations,
  a stronger timeline axis, tighter section spacing, and muted copy links.
- Not applied: moving the findings table above the recommendations. It
  conflicts with the section order in spec §5.

## Proposal C, iteration 4

- Recommendations use the same labelled grid as findings: Problema
  (`data-part="why"`), Prima e dopo, Soluzione with numbered steps
  (`data-part="how"`), Vantaggi (`data-part="benefits"`), Costi
  (`data-part="tradeoffs"`), an expandable migration plan, and a three-part
  conclusion (benefit, cost, what stays valid). The header lists the resolved
  findings as severity chips.
- Findings explain the impact in Problema and add a Vantaggio row
  (`data-part="benefit"`). Copy as issue includes it. Identifiers in prose use
  inline `<code>`.
- Emoji support only the key labels (🔍 Problema, 🛠️ Correzione/Soluzione,
  ✅ Vantaggio, ⚖️ Costi), are `aria-hidden`, and never appear in headings or
  badges. The spec §7 now allows only this use.
- Readable selection: tinted accent on prose, inverted ink on code. Code
  blocks keep their indentation and have a "Copia codice" button that copies
  the resulting code without diff markers or removed lines.
- Sticky section bar with active state, fully clickable table rows, an empty
  state with reset when every filter is off, and "Torna all'elenco" links.
- Order: Sintesi, Criticità (filters and table, `data-section="findings-index"`,
  `id="elenco"`), Raccomandazioni, Dettaglio delle criticità
  (`data-section="findings"`), Note, Evidenze, Interventi. The action list is
  visible first; the detail follows the recommendations. Each table row adds a
  one-line "cosa fare" (`data-part="action"`). This reverses the iteration 3
  decision. The spec now records C as the adopted template.
- A targeted finding no longer fills the whole article with the accent color,
  which hid the code diff colors. Only the badges and title flash briefly, and
  the title keeps an accent underline.

## D · Atlante · Tratto leggero

[D · Atlante](d-atlante.html) is a complete, standalone alternative to
[C · Tabella e dettaglio](c-tabella.html), not a replacement for it.
It preserves C's sample content, section order, evidence states, code diffs,
and interactions. The before/after diagrams align Consumer, Modulo, and
Bucket in the same positions, with the shared policy shown separately after
the change. Their Mermaid sources and accessible descriptions stay aligned.

- The selected design keeps the original Atlas composition: a left section
  index, a central document, and counts to the right of the title.
- The detail navigation includes a nested list of finding types with severity
  shapes and totals. Each link jumps to the first finding of that type, without
  filtering other types. Existing anchor handling reveals a filtered target.
  A submenu click also invokes that handling when the target hash is unchanged.
  The sidebar scrolls on short screens; mobile navigation uses a horizontal
  submenu below the detail link.
- It combines the Civico blue palette with Cartografico's Georgia headings
  and light separators. The finding register shows the action, severity,
  and evidence state without hiding evidence on mobile.
- On narrow screens the index scrolls horizontally, the content stacks,
  and counts follow the verdict. Print hides navigation and controls, shows
  filtered findings, and expands migration details.
- The HTML uses inline CSS and JavaScript. It needs no build, dependencies,
  external fonts, or network access.
- Supporting diagrams use white panels with thin borders and slate title
  labels. Severity colors stay inside the diagrams.
- The mobile header uses tighter spacing without reducing text or button
  sizes. Finding rows distinguish severity from the labelled evidence state.
- Code diffs use 14px text, increased line spacing, and pale green additions
  while retaining the addition and deletion markers.
- The intervention list names three phases: before release, default decisions,
  and a separate release. The original actions and links stay unchanged.

Run the preservation checks with Node.js's built-in test runner:

```sh
node --test docs/specs/local-review-report-creator/templates/d-atlante.test.mjs
```

The checks compare D against C for unchanged report articles, section order,
summary, evidence, finding-register content, baseline script, and anchors.
The revised before/after comparison has separate checks for aligned stages,
the shared policy, Mermaid source, and accessible descriptions.
Intervention checks preserve the action content and links beneath the new
phase headings.
Navigation checks cover finding-type totals and first-detail targets. The
baseline script comparison allows only the same-target submenu reveal listener.

## Shared notes

- Mock data only: a fictional Terraform S3 module review.
- On narrow screens before/after panes stack. The spec §8 tabs are omitted
  for simplicity; decide whether to keep that requirement.
- Session contract check: 0 errors in all three files. Browser render at
  1440px and 390px: no console errors, no horizontal overflow.
