# Local Diagram Embedding

## Default path (2026-11-11)

Lightweight client-side Mermaid is the default. Each diagram keeps its Mermaid
source in the report, and the runtime renders it from the pinned CDN artifact
below. This supersedes the earlier SVG-first default for new reports. SVG
embedding stays available as an optional hardening step, not a requirement.
Do not add SVG bloat, and do not require an external Mermaid CLI.

## Source contract

Retain the Mermaid source even when SVG is available.

Each `figure[data-diagram]` needs a unique safe ID, a caption, one
`.diagram` container with `role="img"` and a meaningful `aria-label`, and a
`.diagram-source` disclosure containing `.mermaid-source`.
Use letters, digits, hyphens, or underscores in IDs, beginning with a letter.
Sources include `accTitle` and `accDescr`, stay theme-neutral, and do not
contain `style`, `classDef`, `linkStyle`, or initialization directives.

Draw only relationships established in the review. Before/after panes must
describe the same proposal. Align unchanged stages as D Atlante does.

## Optional: embed local SVG

Use this only when the user asks for fully offline, static output. Local
rendering avoids sending source text elsewhere.

```sh
python3 <bundle>/scripts/embed_diagrams.py <report.html>
```

The helper uses an installed `mmdc` with strict Mermaid security and HTML
labels disabled. It installs nothing. Absence emits a warning and leaves
the file unchanged; it does not mean embedding passed.
Rendering failure returns an error and preserves the report.

When a controlled browser renderer is available, use it to render sources
locally and save one SVG per figure ID in a dedicated directory. Then run:

```sh
python3 <bundle>/scripts/embed_diagrams.py <report.html> --svg-dir <local-svg-directory>
```

The script rejects missing/symlinked inputs, scripts, event handlers,
foreign objects, external references, entities, duplicate SVG IDs, unsafe
CSS, and unresolved SVG references. Stylesheets must use the SVG root's ID
scope; imports, CSS escapes, and selectors that target root siblings fail.
The output is static: the helper removes Mermaid's two known dash-animation
keyframes and animation declarations. Other at-rules remain unsupported.
It prefixes IDs and rewrites references
for each figure before an atomic write. The source remains unchanged.
Do not paste arbitrary unvalidated SVG directly into report slots.
The sanitizer is a constrained input check, not a universal browser sandbox.

## Degraded fallback

Expose the source and the degradation honestly.

Default `data-diagram-fallback="cdn"` loads the pinned classic browser
artifact only when at least one diagram lacks embedded SVG. If the user
selects `source`, the report requests no renderer and states that SVG is
unavailable. Text and source remain readable without JS in both modes:

| Field | Value |
|---|---|
| Mermaid version | `11.17.2` |
| Artifact | `https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.min.js` |
| SRI | `sha384-EOXBFmc3gx5mb+vn0vPvvGqACToJD24hhacX5Yx+8NUUQrHIle/Qi5Bg9o3zKwW2` |
| Loading | Classic script, `crossorigin="anonymous"`, integrity enforced |
| Runtime | `initialize`, `parse`, then `render`; strict security, HTML labels off |

The exact artifact bytes were retrieved and SHA-384 hashed during bundle
creation. Browser API and offline evidence must still be recorded separately.
No module import chain is assumed to inherit SRI. Nothing posts diagram
source to a rendering service.

On failure, the runtime opens the source and displays an accessible message.
When every diagram contains embedded SVG, no renderer script is requested,
including if `cdn` was selected.

## Offline evidence

Test with an empty cache and network disabled.

A warm-cache render or a CDN-rendered SVG in the live DOM is not an embedded
artifact. Fully rendered offline claims require SVG stored in the HTML file.
If rendering tools or browser checks are unavailable, name that gap.
