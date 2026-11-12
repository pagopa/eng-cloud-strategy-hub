"""Create a new Atlante report without overwriting an existing file."""

import argparse
import re
import sys
from datetime import datetime
from pathlib import Path

from derive_report import derive
from report_contract import TEMPLATE, Document, escape, replace


def make_report(
    *,
    title: str,
    scope: str,
    verdict: str,
    summary: str,
    lang: str = "it",
    zero_findings: bool = False,
    with_recommendations: bool = False,
) -> str:
    if lang not in ("it", "en") or not all(
        v.strip() for v in (title, scope, verdict, summary)
    ):
        raise ValueError("Provide a supported language and non-empty source content")
    it = lang == "it"
    source = TEMPLATE.read_text(encoding="utf-8")
    doc = Document(source)
    header = doc.one("data-slot", "header")
    main = next(n for n in doc.nodes if n.tag == "main")
    nav = next(n for n in doc.nodes if n.tag == "nav")
    page_title = next(n for n in doc.nodes if n.tag == "title")
    root = next(n for n in doc.nodes if n.tag == "html")
    disclaimer = (
        "Questo report presenta una review esistente; non esegue nuove analisi."
        if it
        else "This report presents an existing review; it performs no new analysis."
    )
    header_html = f"""<header data-slot="header"><div class="title-block">
<h1>{escape(title)}</h1><p class="meta">{escape(scope)}</p>
<p class="verdict" data-slot="verdict">{escape(verdict)}</p>
<p class="disclaimer" data-slot="analysis-disclaimer">{disclaimer}</p>
<div class="actionsbar"><button type="button" class="btn" data-print>{"Stampa / PDF" if it else "Print / PDF"}</button>
<button type="button" class="btn" data-expand>{"Espandi tutto" if it else "Expand all"}</button></div>
</div><div class="tally" aria-labelledby="tally-title">
<p class="tally-total" id="tally-title" data-derived="total"></p>
<ul class="counts" data-slot="counts"></ul></div></header>"""
    pending = (
        ""
        if zero_findings
        else (
            "<p data-pending>Inserire le criticità della review sorgente.</p>"
            if it
            else "<p data-pending>Insert the findings from the source review.</p>"
        )
    )
    zero = ' data-zero-findings="true"' if zero_findings else ""
    recommendations = (
        f'<section data-section="recommendations" id="raccomandazioni"><h2>{"Raccomandazioni" if it else "Recommendations"}</h2></section>'
        if with_recommendations
        else ""
    )
    sections = f"""<main id="contenuto">
<section data-section="summary" id="sintesi"><h2>{"Sintesi" if it else "Summary"}</h2><p>{escape(summary)}</p></section>
<section data-section="findings-index" id="elenco"><h2>{"Criticità" if it else "Findings index"}</h2>
<div class="filters" role="group" aria-label="{"Filtra per gravità" if it else "Filter severity"}" data-derived="filters"></div>
<p class="empty" data-empty hidden>{"Nessuna criticità con i filtri attivi." if it else "No findings match the active filters."}
<button type="button" class="btn" data-reset>{"Mostra tutte" if it else "Show all"}</button></p>
<ol class="register" data-derived="index" aria-label="{"Criticità e cosa fare" if it else "Findings and actions"}"></ol></section>
{recommendations}
<section data-section="findings" id="criticita"{zero}><h2>{"Dettaglio criticità" if it else "Finding details"}</h2>{pending}</section>
<section data-section="notes" id="note"><h2>{"Note e limiti" if it else "Notes and limits"}</h2></section>
<section data-section="evidence" id="evidenze"><h2>{"Evidenze" if it else "Evidence"}</h2>
<ul class="checks"><li data-check id="check-source" data-status="not-run">
<span class="st st-not-run">not-run</span><code data-part="check-command">{"Verifiche della review sorgente" if it else "Source review checks"}</code>
<span data-part="check-result">{"Nessuna evidenza di esecuzione ancora inserita; riportare i risultati della fonte." if it else "No execution evidence entered; transcribe the source results."}</span>
</li></ul></section>
<section data-section="actions" id="interventi"><h2>{"Ordine degli interventi" if it else "Order of work"}</h2></section>
</main>"""
    nav_html = f"""<nav class="toc rail" aria-label="{"Indice del report" if it else "Report contents"}">
<div class="rail-inner"><p class="rail-title">{"Atlante della review" if it else "Review atlas"}</p>
<p class="rail-description">{"Dal verdetto alla prova." if it else "From verdict to evidence."}</p>
<ol data-derived="navigation"></ol>
<p class="rail-footer">{disclaimer}</p></div></nav>"""
    source = replace(
        source,
        [
            (
                root.start,
                root.open_end,
                f'<html lang="{lang}" data-report="review" data-template-version="1" data-accent="blue" data-layout="atlante" data-density="comfortable" data-diagram-fallback="cdn">',
            ),
            (page_title.open_end, page_title.close_start, escape(title)),
            (header.start, header.end, header_html),
            (main.start, main.end, sections),
            (nav.start, nav.end, nav_html),
        ],
    )
    if not it:
        source = source.replace("Vai al contenuto", "Skip to content").replace(
            "Documento di review generato da template. Nessuna certificazione del servizio.",
            "Review document generated from a template. Not a service certification.",
        )
    return derive(source)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(".review"))
    parser.add_argument("--date", default=datetime.now().strftime("%Y%m%d"))
    parser.add_argument("--slug", required=True)
    for key in ("title", "scope", "verdict", "summary"):
        parser.add_argument(f"--{key}", required=True)
    parser.add_argument("--lang", choices=("it", "en"), default="it")
    parser.add_argument(
        "--zero-findings",
        action="store_true",
        help="Use only when the source explicitly reports zero findings",
    )
    parser.add_argument(
        "--with-recommendations",
        action="store_true",
        help="Scaffold the recommendations section; omit it when the source has none",
    )
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", args.slug):
        parser.error("--slug must be lowercase words separated by hyphens")
    if not re.fullmatch(r"\d{8}", args.date):
        parser.error("--date must be a valid YYYYMMDD date")
    try:
        datetime.strptime(args.date, "%Y%m%d")
    except ValueError:
        parser.error("--date must be a valid YYYYMMDD date")
    target = args.root / f"{args.date}-review-{args.slug}" / "report.html"
    try:
        result = make_report(
            title=args.title,
            scope=args.scope,
            verdict=args.verdict,
            summary=args.summary,
            lang=args.lang,
            zero_findings=args.zero_findings,
            with_recommendations=args.with_recommendations,
        )
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("x", encoding="utf-8") as handle:
            handle.write(result)
    except (OSError, UnicodeError, ValueError, KeyError) as error:
        print(f"Cannot create report: {error}", file=sys.stderr)
        return 1
    print(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
