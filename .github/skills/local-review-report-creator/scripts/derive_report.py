"""Explicitly derive index, navigation, and counts from report findings."""

import argparse
import sys
from pathlib import Path

from report_contract import (
    LABELS,
    SEVERITIES,
    Document,
    atomic_write,
    escape,
    invariant_errors,
    replace,
)


def icon(severity: str) -> str:
    return f'<svg class="ico sev-{severity}" viewBox="0 0 24 24" aria-hidden="true"><use href="#sev-{severity}"/></svg>'


def derive(source: str) -> str:
    doc = Document(source)
    errors = doc.errors + invariant_errors(doc)
    if errors:
        raise ValueError("; ".join(errors))
    root = next(n for n in doc.nodes if n.tag == "html")
    lang = root.attrs["lang"]
    labels = dict(zip(SEVERITIES, LABELS[lang]))
    findings = doc.select("data-finding")
    groups = {
        severity: [f for f in findings if f.attrs.get("data-severity") == severity]
        for severity in SEVERITIES
    }
    if sum(map(len, groups.values())) != len(findings):
        raise ValueError(
            "Unsupported severity; obtain the source adapter before deriving"
        )
    edits = []
    counts = []
    for severity, group in groups.items():
        link = f' href="#{escape(group[0].attrs["id"])}"' if group else ""
        tag = "a" if group else "span"
        counts.append(
            f'<li data-count="{severity}"><{tag}{link}>{icon(severity)}'
            f'<span>{labels[severity]}</span><span class="n">{len(group)}</span></{tag}></li>'
        )
    count_slot = doc.one("data-slot", "counts")
    edits.append((count_slot.open_end, count_slot.close_start, "".join(counts)))
    total = sum(len(groups[s]) for s in SEVERITIES if s != "note")
    total_text = (
        ("punto da rivedere" if total == 1 else "punti da rivedere")
        if lang == "it"
        else ("finding to review" if total == 1 else "findings to review")
    )
    note_text = (
        ("nota informativa" if len(groups["note"]) == 1 else "note informative")
        if lang == "it"
        else (
            "informational note" if len(groups["note"]) == 1 else "informational notes"
        )
    )
    tally = doc.one("data-derived", "total")
    edits.append(
        (
            tally.open_end,
            tally.close_start,
            f'<span class="big">{total}</span> {total_text}'
            f'<span class="meta">{len(groups["note"])} {note_text}</span>',
        )
    )
    rows = []
    for severity in SEVERITIES[:-1]:
        for finding in groups[severity]:
            titles = finding.tags("h3")
            actions = finding.select("data-part", "action")
            if len(titles) != 1 or len(actions) != 1 or not actions[0].text:
                raise ValueError(
                    f"Finding {finding.attrs.get('id')} needs one title and source-derived action"
                )
            evidence = finding.select("class")
            evidence_label = next(
                (n.text for n in evidence if "ev" in n.attrs["class"].split()), ""
            )
            if not evidence_label:
                raise ValueError("Each finding needs a visible evidence label")
            rows.append(
                f'<li data-row="{severity}"><div class="finding-id sev-{severity}">'
                f"{icon(severity)}<span>{escape(finding.attrs['data-source-id'])}</span></div>"
                f'<div class="register-copy"><h3><a href="#{escape(finding.attrs["id"])}">'
                f'{escape(titles[0].text)}</a></h3><p class="todo" data-part="action">'
                f'{escape(actions[0].text)}</p></div><div class="evidence">'
                f'<span class="severity-label">{labels[severity]}</span>'
                f'<span class="ev">{escape(evidence_label)}</span></div></li>'
            )
    index = doc.one("data-derived", "index")
    edits.append((index.open_end, index.close_start, "".join(rows)))
    filters = doc.one("data-derived", "filters")
    edits.append(
        (
            filters.open_end,
            filters.close_start,
            "".join(
                f'<button type="button" class="chip" aria-pressed="true" data-filter="{s}">'
                f'{icon(s)}{labels[s]} <span class="n">{len(groups[s])}</span></button>'
                for s in SEVERITIES[:-1]
                if groups[s]
            ),
        )
    )
    navigation = doc.one("data-derived", "navigation")
    sections = doc.select("data-section")
    links = []
    for index_number, section in enumerate(sections, 1):
        headings = section.tags("h2")
        if not headings or not section.attrs.get("id"):
            raise ValueError("Each section needs a heading and anchor")
        types = ""
        if section.attrs["data-section"] == "findings":
            types = (
                f'<ul class="rail-types" aria-label="{"Tipologie di criticità" if lang == "it" else "Finding types"}">'
                + "".join(
                    f'<li><a href="#{escape(groups[s][0].attrs["id"])}">{icon(s)}'
                    f'<span>{labels[s]}</span><span class="n">{len(groups[s])}</span></a></li>'
                    for s in SEVERITIES[:-1]
                    if groups[s]
                )
                + "</ul>"
            )
        links.append(
            f'<li><a href="#{escape(section.attrs["id"])}">'
            f'<span class="num" aria-hidden="true">{index_number:02}</span>'
            f"{escape(headings[0].text)}</a>{types}</li>"
        )
    edits.append((navigation.open_end, navigation.close_start, "".join(links)))
    return replace(source, edits)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    try:
        result = derive(args.report.read_text(encoding="utf-8"))
        atomic_write(args.report, result)
    except (OSError, UnicodeError, ValueError, KeyError) as error:
        print(f"Cannot derive report: {error}", file=sys.stderr)
        return 1
    print(args.report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
