# Atlante Components

Replace sample text with source-backed content. These snippets show shapes,
not review conclusions. Put findings inside `data-section="findings"` and
notes inside `data-section="notes"`. Keep one h3 per finding.

## Finding

The hidden action is the source for the derived register, not new advice.

```html
<article class="finding" data-finding id="finding-cache"
  data-source-review="cache-review" data-source-id="F7"
  data-source-severity="IMPORTANT" data-severity="important"
  data-evidence="documented" data-confidence="medium"
  data-conditional="true">
  <div class="badges">
    <span class="sev sev-important"><svg class="ico" viewBox="0 0 24 24"
      aria-hidden="true"><use href="#sev-important"/></svg>Importante</span>
    <span class="ev ev-documented">Documentato</span>
  </div>
  <h3>Source finding title</h3>
  <p class="meta" data-part="source-metadata">cache-review · F7 · IMPORTANT · medium</p>
  <p data-part="action" hidden>Source-derived imperative action.</p>
  <dl class="parts">
    <div class="row row-problem"><dt>Problema</dt>
      <dd data-part="problem"><p>Problem and impact from the source.</p></dd></div>
    <div class="row row-example"><dt>Esempio</dt>
      <dd data-part="example"><p>Concrete source example.</p></dd></div>
    <div class="row row-fix"><dt>Correzione</dt>
      <dd data-part="fix"><p>Source fix, with a diff when supplied.</p></dd></div>
    <div class="row row-benefit"><dt>Vantaggio</dt>
      <dd data-part="benefit"><p>Source-supported outcome.</p></dd></div>
    <div class="row row-limits"><dt>Condizioni</dt>
      <dd data-part="conditions"><p>Applicability condition from the source.</p></dd></div>
    <div class="row row-sources"><dt>Fonti</dt>
      <dd data-part="sources"><p>Exact source location or valid link.</p></dd></div>
  </dl>
  <div class="tools">
    <button type="button" class="link" data-copy-link hidden>Copia link</button>
    <button type="button" class="link" data-copy-issue hidden>Copia come issue</button>
    <span class="status" role="status"></span>
    <a class="back" href="#elenco">Torna all'elenco</a>
  </div>
</article>
```

For `blocker`, use `#sev-blocker` (octagon); for `improvement`, use
`#sev-improvement` (circle). Preserve the matching text label.
Omit unsupported optional parts and absent confidence, including its visible
value. For unconditional findings, omit `data-conditional` and conditions.
Use `limits` for additional source uncertainty.

## Note

Use `data-severity="note"`, the original source severity, and `#sev-note`
(info shape). Use `data-part="indication"` instead of `fix`.
Problem/context and sources remain required. Omit the action and optional
example when absent. A note never receives a findings-index row.

## Recommendation

Use this only for an existing proposal in the review.

```html
<article class="reco" data-recommendation id="recommendation-cache"
  data-refs="finding-cache" data-structural="true">
  <header><h3>Source proposal title</h3>
    <p class="lede">Source-backed proposal.</p>
    <p class="refs"><a class="ref" href="#finding-cache">F7</a></p>
  </header>
  <dl class="parts">
    <div class="row row-problem"><dt>Problema</dt>
      <dd data-part="why"><p>Current state and consequences.</p></dd></div>
    <div class="row row-ba"><dt>Prima e dopo</dt><dd>
      <div class="ba" data-part="before-after">
        <!-- Insert one diagram figure with data-side="before"
             and one with data-side="after", using the component below. -->
      </div>
    </dd></div>
    <div class="row row-fix"><dt>Soluzione</dt>
      <dd data-part="how"><ol class="steps"><li>Source step.</li></ol></dd></div>
    <div class="row row-benefit"><dt>Vantaggi</dt>
      <dd data-part="benefits"><ul class="gains">
        <li><b>Source benefit</b>Explanation linked to
          <a href="#finding-cache">F7</a>.</li>
      </ul></dd></div>
  </dl>
  <footer data-part="conclusion"><dl class="outcome">
    <div><dt>Vantaggio</dt><dd>Supported benefit.</dd></div>
    <div><dt>Costo</dt><dd>Source cost, or explicitly not specified.</dd></div>
    <div><dt>Resta valido</dt><dd>What the source says remains valid.</dd></div>
  </dl></footer>
</article>
```

When costs are supplied, add `data-part="tradeoffs"` in the labelled grid.
For non-structural proposals, omit `data-structural` and the before/after row.
Do not fill an unspecified cost or validity claim with an invented one.

## Diagram

Give each figure a safe unique ID. Use `data-side` only in before/after.
Keep the source inside a disclosure so it works without JavaScript.

```html
<figure data-diagram id="diagram-cache-before" data-side="before">
  <figcaption><strong>Prima</strong> · Source-backed relationship</figcaption>
  <div class="diagram" role="img" aria-label="Client reads from the cache."></div>
  <details class="diagram-source"><summary>Sorgente Mermaid</summary>
    <pre class="mermaid-source">flowchart LR
  accTitle: Cache read
  accDescr: Client reads from the cache.
  C[Client] --&gt; K[Cache]</pre>
  </details>
</figure>
```

## Code diff

Keep each logical line inside `.ln`; preserve indentation in its last span.
Removed lines use `.del`; added lines use `.add`.

```html
<figure class="code">
  <figcaption><span class="file">settings.conf</span> · source fix
    <button type="button" class="link copy-code" data-copy-code hidden>Copia codice</button>
  </figcaption>
  <pre><code><span class="ln del"><span class="mk">-</span><span>ttl = 0</span></span><span class="ln add"><span class="mk">+</span><span>ttl = 600</span></span></code></pre>
</figure>
```

The copy button emits only resulting lines, without markers or removed code.

## Summary

Three parts, all source-backed: the outcome, a labelled grid, and optional
adapter details. Keep the section's existing attributes.

```html
<section data-section="summary" id="sintesi"><h2>Sintesi</h2>
  <p class="summary-lead">Source-backed outcome in one or two sentences.</p>
  <dl class="summary-grid">
    <div><dt>Ambito</dt><dd>Scope from the source.</dd></div>
    <div><dt>Esito</dt><dd>Source verdict, exactly as supplied.</dd></div>
  </dl>
  <details><summary>Dettagli dell'adattatore</summary>
    <p>Severity mapping and any user-approved custom adapter.</p>
  </details>
</section>
```

## Flow visualization

Add an opening `figure.viz` directly after a finding's `p.meta` when the
finding describes a flow or chain. Keep the Mermaid source as in Diagram.

```html
<figure data-diagram class="viz" id="viz-cache-flow">
  <figcaption>Sequenza descritta nella fonte</figcaption>
  <div class="diagram" role="img" aria-label="Client reads from the cache."></div>
  <details class="diagram-source"><summary>Sorgente Mermaid</summary>
    <pre class="mermaid-source">flowchart LR
  accTitle: Cache read
  accDescr: Client reads from the cache.
  C[Client] --&gt; K[Cache]</pre>
  </details>
</figure>
```

## Read-only snippet in Problema

Show source code inside `data-part="problem"` as a read-only `figure.code`.
Cite `path:line` in the figcaption. Use no diff markers and no copy button.

```html
<figure class="code">
  <figcaption><span class="file">modules/cache/main.tf:12</span></figcaption>
  <pre><code>ttl = 0</code></pre>
</figure>
```

## Clean table

Use tables only for comparisons from the source. Give each table a caption,
`scope` on every header cell, and no nested tables or decorative colour. On
narrow screens the table scrolls horizontally.

```html
<table>
  <caption>Comparison from the source</caption>
  <thead><tr><th scope="col">Voce</th><th scope="col">Valore</th></tr></thead>
  <tbody><tr><td>Source item</td><td>Source value</td></tr></tbody>
</table>
```

## Check and free section

```html
<li data-check id="check-parser" data-status="blocked">
  <span class="st st-blocked">blocked</span>
  <code data-part="check-command">source command</code>
  <span data-part="check-result">The source records why execution was blocked.</span>
</li>
```

Place checks inside the evidence section's `.checks` list.
A case-specific section uses `data-section="custom"`, a unique ID, and an h2.
Comparison tables, calculations, timelines, and extra details may extend
these components without changing the invariant shell.
