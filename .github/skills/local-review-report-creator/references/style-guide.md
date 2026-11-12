# D Atlante Style Guide

## Template ownership

Use the actual D Atlante composition shipped in `assets/template.html`.

The asset retains the prototype's CSS, serif headings, blue ink, left rail,
right-hand tally, finding register, labelled detail grid, before/after
panels, code diffs, intervention phases, severity shapes, and print layout.
The bundled runtime corrects clipboard visibility, complete issue copying,
same-target navigation, print restoration, and language handling.
The example Terraform content is illustrative only; scaffolding replaces it.

Treat `css`, `layout`, `severity-icons`, and `script` as four invariant blocks.
The checker compares their full markup against this exact bundled version,
normalizing line endings only. Unknown or repeated blocks fail.
No earlier version is implicitly accepted.

## Adjustable values

- `data-layout`: `atlante`.
- `data-template-version`: `1`.
- `lang`: `it` or `en`.
- `data-accent`: `blue` (default), `terracotta`, `green`, `violet`, `graphite`.
- `data-density`: `comfortable` (default) or `compact`; body stays at least 16px.
- `data-diagram-fallback`: `cdn` (default, pinned Mermaid with SRI) or `source`
  (no renderer request; source only).

Use the existing purpose tokens for custom components. Keep the white/light
blue Atlas surfaces, light theme under dark OS preferences, and Georgia
headings. Density changes spacing rather than shrinking body text.
Do not reintroduce the superseded C terracotta/system-heading design.

## Components and browser surfaces

- Navigation: sticky side rail on desktop; horizontally scrollable on mobile.
  Finding-type links jump to the first detail, not a severity-filter preset.
- Findings: source action first in the register; full details later.
  Shapes and labels communicate severity without relying on color.
- Before/after: side by side on wide screens, stacked on narrow screens,
  side by side in print. Do not add tabs.
- Code: pale diff backgrounds, distinct markers, 14px code text, preserved
  indentation, non-selectable gutter, resulting-code clipboard action.
- Selection: readable prose and inverted code selection.
- Targets: highlight the title/badges, never fill the entire finding.
- Print: hide controls/navigation, show filtered findings, open disclosures,
  then restore the screen state.
- Motion: respect `prefers-reduced-motion`.

## Free components

Use tables for comparisons (caption, `th scope`, no nested tables),
timelines for chronology, and diagrams for relationships. Add supporting styles only in the empty custom-style slot.
Do not override invariant selectors, core tokens, visibility, or controls.
Hash checks cannot prove that arbitrary custom CSS is harmless.

Avoid nested cards, thick colored side borders, hero metrics, decorative
animations, web fonts, emoji outside the four original hidden part-label
markers, and decorative diagrams. D hides those emoji markers.
Normal text and accent links require at least 4.5:1 contrast on their actual
surfaces. Test the rendered state; the structural checker is not a contrast
or accessibility certification.
