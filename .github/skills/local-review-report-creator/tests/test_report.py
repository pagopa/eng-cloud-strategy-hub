import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

BUNDLE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BUNDLE / "scripts"))

import derive_report
import embed_diagrams
import report_contract as contract
import scaffold_report

FINDING = """
<article class="finding" data-finding id="finding-1"
 data-source-review="review-a" data-source-id="A-17"
 data-source-severity="BLOCKER" data-severity="blocker"
 data-evidence="documented" data-confidence="high">
 <div class="badges"><span class="sev">Bloccante</span>
 <span class="ev">Documentato</span></div>
 <h3>Retention lacks an upper bound</h3>
 <p data-part="source-metadata">review-a · A-17 · BLOCKER · high</p>
 <dl class="parts">
 <div class="row"><dt>Problema</dt><dd data-part="problem">Retention is unbounded.</dd></div>
 <div class="row"><dt>Esempio</dt><dd data-part="example">A record remains after expiry.</dd></div>
 <div class="row"><dt>Correzione</dt><dd data-part="fix"><p>Set the documented expiry.</p>
 <figure class="code"><figcaption><span class="file">retention.conf</span>
 <button type="button" class="link copy-code" data-copy-code hidden>Copia codice</button></figcaption>
 <pre><code><span class="ln del"><span class="mk">-</span><span>ttl = 0</span></span><span class="ln add"><span class="mk">+</span><span>ttl = 600</span></span></code></pre></figure></dd></div>
 <div class="row"><dt>Azione</dt><dd data-part="action">Configure expiry.</dd></div>
 <div class="row"><dt>Fonti</dt><dd data-part="sources">source-review.md</dd></div>
 </dl>
 <details><summary>Source detail</summary><p>Exact source example.</p></details>
 <div class="tools"><button type="button" class="link" data-copy-link hidden>Copia link</button>
 <button type="button" class="link" data-copy-issue hidden>Copia come issue</button>
 <span class="status" role="status"></span><a class="back" href="#elenco">Torna all'elenco</a></div>
</article>
"""

DIAGRAM = """
<figure data-diagram id="diagram-a"><figcaption>Retention flow</figcaption>
<div class="diagram" role="img" aria-label="Records expire"></div>
<details class="diagram-source"><summary>Source</summary>
<pre class="mermaid-source">flowchart LR
 accTitle: Expiry
 accDescr: Records expire
 A[Record] --&gt; B[Expiry]</pre></details></figure>
"""


def zero_report(**options):
    return scaffold_report.make_report(
        title="Retention review",
        scope="records",
        verdict="No defects reported.",
        summary="The supplied review reports no defects.",
        lang="it",
        zero_findings=True,
        **options,
    )


def with_findings(finding=FINDING, **options):
    source = (
        zero_report(**options)
        .replace("No defects reported.", "Correct retention before release.")
        .replace(
            "The supplied review reports no defects.",
            "The source review reports a retention defect.",
        )
    )
    doc = contract.Document(source)
    section = doc.one("data-section", "findings")
    source = contract.replace(
        source,
        [
            (
                section.start,
                section.end,
                '<section data-section="findings" id="criticita"><h2>Dettaglio criticità</h2>'
                + finding
                + "</section>",
            ),
            (
                doc.one("data-section", "actions").open_end,
                doc.one("data-section", "actions").close_start,
                '<h2>Interventi</h2><ol class="actions"><li><a href="#finding-1">'
                "Configure expiry before release.</a></li></ol>",
            ),
        ],
    )
    return derive_report.derive(source)


class ReportTests(unittest.TestCase):
    def codes(self, source, base=None):
        return {d["rule"] for d in contract.check(source, base=base)}

    def test_explicit_zero_findings_is_valid_and_has_no_demo_content(self):
        report = zero_report()
        errors = [d for d in contract.check(report) if d["severity"] == "error"]
        self.assertEqual(errors, [])
        self.assertNotIn("Terraform S3 Bucket", report)
        self.assertNotIn("enable_versioning", report)
        self.assertNotIn("blocker-1", report)
        self.assertEqual(len(contract.Document(report).select("data-finding")), 0)

    def test_unfinished_scaffold_is_not_an_empty_review(self):
        report = scaffold_report.make_report(
            title="Pending",
            scope="records",
            verdict="Review supplied",
            summary="Details pending.",
            lang="it",
        )
        self.assertIn("content-pending", self.codes(report))
        self.assertIn("zero-findings", self.codes(report))

    def test_derivation_is_idempotent_and_preserves_invariants(self):
        report = with_findings()
        self.assertEqual(report, derive_report.derive(report))
        self.assertNotIn("invariant", self.codes(report))
        self.assertEqual(
            [d for d in contract.check(report) if d["severity"] == "error"], []
        )
        doc = contract.Document(report)
        self.assertEqual(len(doc.select("data-row")), 1)
        self.assertEqual(doc.one("data-count", "blocker").text.count("1"), 1)
        self.assertIn("Configure expiry.", doc.one("data-row", "blocker").text)
        self.assertIn('href="#finding-1"', report)

    def test_checker_defective_mutations(self):
        report = with_findings()
        mutations = json.loads((BUNDLE / "tests/fixtures/defects.json").read_text())
        for case in mutations:
            with self.subTest(case=case["rule"]):
                self.assertIn(case["needle"], report)
                defective = report.replace(case["needle"], case["replacement"], 1)
                self.assertIn(case["rule"], self.codes(defective))

    def test_invariants_normalize_only_line_endings(self):
        self.assertNotIn("invariant", self.codes(zero_report().replace("\n", "\r\n")))
        self.assertIn(
            "invariant",
            self.codes(zero_report().replace("--ink:#2b2118", "--ink: #2b2118", 1)),
        )

    def test_invariant_duplicates_and_html_nesting_fail(self):
        source = zero_report()
        original = contract.Document(source).one("data-invariant", "layout")
        self.assertIn(
            "invariant",
            self.codes(
                source.replace(
                    "</head>", contract.Document(source).raw(original) + "</head>"
                )
            ),
        )
        self.assertIn(
            "html-nesting", self.codes(source.replace("</main>", "</article></main>"))
        )

    def test_source_adapter_requires_explicit_approval_for_unknown_scales(self):
        native = with_findings()
        wrong = native.replace('data-severity="blocker"', 'data-severity="important"')
        self.assertIn("severity-adapter", self.codes(wrong))
        unknown = native.replace(
            'data-source-severity="BLOCKER"', 'data-source-severity="critical"'
        ).replace("BLOCKER · high", "critical · high")
        self.assertIn("severity-adapter", self.codes(unknown))
        adapter = '<table data-severity-adapter data-approved="true"><tbody><tr data-adapter-source="critical" data-adapter-target="blocker"><td>critical</td><td>blocker</td></tr></tbody></table>'
        unknown = unknown.replace("<h2>Sintesi</h2>", "<h2>Sintesi</h2>" + adapter)
        self.assertNotIn("severity-adapter", self.codes(unknown))

    def test_conditional_requires_condition_not_a_new_evidence_state(self):
        report = with_findings().replace(
            'data-confidence="high"', 'data-confidence="high" data-conditional="true"'
        )
        self.assertIn("conditions", self.codes(report))
        report = report.replace(
            "</dl>",
            '<div class="row"><dt>Condition</dt><dd data-part="conditions">Only with replication enabled.</dd></div></dl>',
            1,
        )
        self.assertNotIn("conditions", self.codes(report))

    def test_total_navigation_and_filter_counts_are_checked(self):
        report = with_findings()
        self.assertIn(
            "derived-content",
            self.codes(
                report.replace(
                    '<span class="big">1</span>', '<span class="big">9</span>'
                )
            ),
        )
        self.assertIn(
            "derived-content",
            self.codes(
                report.replace('data-filter="blocker"', 'data-filter="important"')
            ),
        )

    def test_refused_patterns_are_warnings_and_literal_code_is_not_prose(self):
        report = zero_report().replace(
            "The supplied review reports no defects.", "🚀 Summary"
        )
        self.assertIn("decorative-emoji", self.codes(report))
        report = zero_report().replace(
            '<style data-slot="custom-style">',
            '<style data-slot="custom-style">.example{border-left:4px solid red}',
        )
        self.assertIn("side-border", self.codes(report))

    def test_all_accents_have_readable_link_contrast(self):
        def luminance(color):
            channels = [int(color[i : i + 2], 16) / 255 for i in (0, 2, 4)]
            linear = [
                v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
                for v in channels
            ]
            return sum(a * b for a, b in zip(linear, (0.2126, 0.7152, 0.0722)))

        for color in ("1745ad", "a34324", "246044", "6e3ab8", "3d4452", "4c5d7a"):
            for surface in ("ffffff", "eef2fa"):
                with self.subTest(color=color, surface=surface):
                    ratio = (luminance(surface) + 0.05) / (luminance(color) + 0.05)
                    self.assertGreaterEqual(ratio, 4.5)

    def test_source_metadata_and_notes_are_distinct(self):
        note = (
            FINDING.replace('id="finding-1"', 'id="note-1"')
            .replace('data-severity="blocker"', 'data-severity="note"')
            .replace('data-source-severity="BLOCKER"', 'data-source-severity="NOTE"')
        )
        note = (
            note.replace('data-part="fix"', 'data-part="indication"')
            .replace('data-part="example"', 'data-part="extra"')
            .replace("BLOCKER · high", "NOTE · high")
        )
        source = zero_report()
        doc = contract.Document(source)
        notes = doc.one("data-section", "notes")
        source = contract.replace(
            source, [(notes.open_end, notes.close_start, "<h2>Note</h2>" + note)]
        )
        report = derive_report.derive(source)
        self.assertEqual(len(contract.Document(report).select("data-row")), 0)
        self.assertNotIn("finding-part", self.codes(report))
        self.assertNotIn("note-placement", self.codes(report))

    def test_source_ids_scoped_to_review(self):
        other = (
            FINDING.replace('id="finding-1"', 'id="finding-2"')
            .replace('data-source-review="review-a"', 'data-source-review="review-b"')
            .replace("review-a ·", "review-b ·")
        )
        report = with_findings(FINDING + other)
        self.assertNotIn("source-identity", self.codes(report))
        self.assertIn(
            "source-identity", self.codes(report.replace("review-b", "review-a"))
        )

    def test_missing_source_evidence_remains_unverified(self):
        report = with_findings(
            FINDING.replace('data-evidence="documented"', 'data-evidence="unverified"')
        )
        self.assertIn("unverified", report)
        conditional = report.replace(
            'data-evidence="unverified"', 'data-evidence="conditional"'
        )
        self.assertIn("evidence-state", self.codes(conditional))

    def test_links_and_literal_markup(self):
        report = with_findings(
            FINDING.replace(
                "A record remains", "&lt;script&gt;alert(1)&lt;/script&gt; remains"
            )
        )
        self.assertNotIn("<script>alert(1)</script>", report)
        self.assertNotIn("active-content", self.codes(report))
        with tempfile.TemporaryDirectory() as directory:
            linked = report.replace(
                "source-review.md</dd>", '<a href="missing.md">source</a></dd>'
            )
            self.assertIn("file-link", self.codes(linked, Path(directory)))

    def test_default_scaffold_uses_cdn_fallback_and_omits_empty_recommendations(self):
        report = zero_report()
        self.assertIn('data-diagram-fallback="cdn"', report)
        self.assertNotIn('data-section="recommendations"', report)
        self.assertNotIn("empty-recommendations", self.codes(report))
        self.assertEqual(
            [d for d in contract.check(report) if d["severity"] == "error"], []
        )

    def test_empty_recommendations_section_is_rejected(self):
        report = zero_report(with_recommendations=True)
        self.assertIn('data-section="recommendations"', report)
        self.assertIn("empty-recommendations", self.codes(report))

    def test_recommendations_flag_on_cli_scaffolds_the_section(self):
        with tempfile.TemporaryDirectory() as directory:
            args = [
                sys.executable,
                str(BUNDLE / "scripts/scaffold_report.py"),
                "--root",
                directory,
                "--date",
                "20261111",
                "--slug",
                "records",
                "--title",
                "Records",
                "--scope",
                "Review",
                "--verdict",
                "No defects.",
                "--summary",
                "No defects supplied by the source.",
                "--zero-findings",
                "--with-recommendations",
            ]
            created = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(created.returncode, 0, created.stderr)
            report = Path(directory) / "20261111-review-records/report.html"
            self.assertIn('data-section="recommendations"', report.read_text())
            self.assertIn("empty-recommendations", self.codes(report.read_text()))

    def test_opening_flow_diagram_validates_inside_finding(self):
        viz = DIAGRAM.replace("<figure data-diagram", '<figure data-diagram class="viz"')
        finding = FINDING.replace(
            '<p data-part="source-metadata">',
            viz + '<p data-part="source-metadata">',
        )
        report = with_findings(finding)
        self.assertEqual(
            [d for d in contract.check(report) if d["severity"] == "error"], []
        )

    def test_unembedded_diagram_uses_runtime_fallback_without_warning(self):
        report = with_findings(FINDING.replace("</article>", DIAGRAM + "</article>"))
        self.assertNotIn("diagram-unembedded", self.codes(report))

    def test_diagram_embedding_replaces_source_with_static_svg(self):
        report = with_findings(FINDING.replace("</article>", DIAGRAM + "</article>"))
        svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><defs><marker id="arrow"/></defs><path marker-end="url(#arrow)"/></svg>'
        embedded = embed_diagrams.embed(report, {"diagram-a": svg})
        self.assertNotIn("diagram-unembedded", self.codes(embedded))
        self.assertIn("diagram-a--arrow", embedded)
        self.assertIn("accTitle: Expiry", embedded)
        for unsafe in (
            (BUNDLE / "tests/fixtures/unsafe.svg").read_text(),
            '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
            '<svg xmlns="http://www.w3.org/2000/svg"><path onclick="alert(1)"/></svg>',
            '<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.com/x"/></svg>',
            '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject/></svg>',
        ):
            with self.subTest(svg=unsafe), self.assertRaises(ValueError):
                embed_diagrams.embed(report, {"diagram-a": unsafe})

    def test_real_mermaid_output_embeds_as_static_scoped_svg(self):
        source = (BUNDLE / "tests/fixtures/mermaid-rendered.svg").read_text()
        result = embed_diagrams.safe_svg(source, "diagram-a")
        self.assertIn("diagram-a--probe-no-html", result)
        self.assertNotIn("@keyframes", result)
        self.assertNotIn("foreignObject", result)

    def test_svg_styles_cannot_escape_their_diagram(self):
        source = '<svg xmlns="http://www.w3.org/2000/svg" id="root"><style>#root text { fill: black; }</style><text>Expiry</text></svg>'
        self.assertIn("diagram-a--root", embed_diagrams.safe_svg(source, "diagram-a"))
        for css in (
            "body{display:none}",
            "#root + p{display:none}",
            "@\\69mport 'remote.css';",
        ):
            with self.subTest(css=css), self.assertRaises(ValueError):
                embed_diagrams.safe_svg(
                    source.replace("#root text { fill: black; }", css), "diagram-a"
                )

    def test_local_renderer_disables_html_labels_at_both_config_levels(self):
        source = with_findings(FINDING.replace("</article>", DIAGRAM + "</article>"))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.html"
            path.write_text(source)

            def renderer(args, **kwargs):
                config = json.loads(Path(args[args.index("-c") + 1]).read_text())
                self.assertIs(config["htmlLabels"], False)
                self.assertIs(config["flowchart"]["htmlLabels"], False)
                Path(args[args.index("-o") + 1]).write_text(
                    '<svg xmlns="http://www.w3.org/2000/svg"><text>Expiry</text></svg>'
                )

            with (
                patch.object(sys, "argv", ["embed_diagrams.py", str(path)]),
                patch.object(
                    embed_diagrams.shutil, "which", return_value="/synthetic/mmdc"
                ),
                patch.object(embed_diagrams.subprocess, "run", side_effect=renderer),
            ):
                self.assertEqual(embed_diagrams.main(), 0)
            self.assertNotIn("diagram-unembedded", self.codes(path.read_text()))

    def test_technical_collega_is_not_framing(self):
        report = zero_report().replace(
            "The supplied review reports no defects.",
            "Il modulo collega i due archivi.",
        )
        self.assertNotIn("tone", self.codes(report))
        self.assertIn(
            "tone",
            self.codes(
                report.replace(
                    "Il modulo collega i due archivi.",
                    "Caro collega, ecco il risultato.",
                )
            ),
        )

    def test_recommendation_requires_supported_parts_and_targets(self):
        recommendation = """
        <article data-recommendation id="r-1" data-refs="finding-1">
        <header><h3>Central expiry</h3></header>
        <p data-part="why">Retention is scattered.</p>
        <p data-part="how">Reuse the existing expiry service.</p>
        <p data-part="benefits">Consistent retention.</p>
        <footer data-part="conclusion">One expiry policy.</footer></article>"""
        report = with_findings(with_recommendations=True)
        doc = contract.Document(report)
        section = doc.one("data-section", "recommendations")
        report = contract.replace(
            report,
            [
                (
                    section.open_end,
                    section.close_start,
                    "<h2>Raccomandazioni</h2>" + recommendation,
                )
            ],
        )
        self.assertNotIn("recommendation-part", self.codes(report))
        self.assertIn(
            "recommendation-part",
            self.codes(report.replace('data-part="why"', 'data-part="missing"', 1)),
        )
        self.assertIn(
            "recommendation-reference",
            self.codes(report.replace('data-refs="finding-1"', 'data-refs="missing"')),
        )

    def test_cli_no_overwrite_and_checker_read_only(self):
        with tempfile.TemporaryDirectory() as directory:
            args = [
                sys.executable,
                str(BUNDLE / "scripts/scaffold_report.py"),
                "--root",
                directory,
                "--date",
                "20261111",
                "--slug",
                "records",
                "--title",
                "Records",
                "--scope",
                "Review",
                "--verdict",
                "No defects.",
                "--summary",
                "No defects supplied by the source.",
                "--zero-findings",
            ]
            created = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(created.returncode, 0, created.stderr)
            report = Path(directory) / "20261111-review-records/report.html"
            original = report.read_bytes()
            checked = subprocess.run(
                [
                    sys.executable,
                    str(BUNDLE / "scripts/check_report.py"),
                    str(report),
                    "--format",
                    "json",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
            self.assertEqual(report.read_bytes(), original)
            self.assertEqual(subprocess.run(args, capture_output=True).returncode, 1)
            self.assertEqual(report.read_bytes(), original)
            unsafe = args.copy()
            unsafe[unsafe.index("records")] = "../escape"
            self.assertEqual(subprocess.run(unsafe, capture_output=True).returncode, 2)
            bad_date = args.copy()
            bad_date[bad_date.index("20261111")] = "2026111"
            self.assertEqual(
                subprocess.run(bad_date, capture_output=True).returncode, 2
            )


class TemplateAtlanteStylesTests(unittest.TestCase):
    TEMPLATE_TEXT = (BUNDLE / "assets" / "template.html").read_text(encoding="utf-8")

    def test_generic_tables_are_collapsed_captioned_and_scrollable(self):
        self.assertRegex(self.TEMPLATE_TEXT, r"table\{[^}]*border-collapse:collapse")
        self.assertRegex(self.TEMPLATE_TEXT, r"table\{[^}]*width:100%")
        self.assertRegex(self.TEMPLATE_TEXT, r"caption\{[^}]*")
        self.assertRegex(self.TEMPLATE_TEXT, r"th\{[^}]*border-bottom")
        self.assertRegex(self.TEMPLATE_TEXT, r"(overflow-x:auto|overflow-wrap:anywhere)")

    def test_summary_has_lead_grid_and_collapsible_adapter_styles(self):
        self.assertIn(".summary-lead{", self.TEMPLATE_TEXT)
        self.assertIn(".summary-grid{", self.TEMPLATE_TEXT)
        self.assertRegex(self.TEMPLATE_TEXT, r"\.summary-grid\{[^}]*grid-template-columns")
        self.assertRegex(self.TEMPLATE_TEXT, r"details[^{]*\{")

    def test_finding_viz_has_spacing_below_meta(self):
        self.assertRegex(self.TEMPLATE_TEXT, r"\.finding>\.meta\+figure\.viz\{[^}]*margin")

    def test_problem_part_hosts_read_only_code_figure(self):
        problems = re.findall(r'data-part="problem">(.*?)</dd>', self.TEMPLATE_TEXT, re.S)
        self.assertTrue(problems)
        self.assertTrue(any('<figure class="code"' in part for part in problems))

    def test_default_diagram_fallback_is_cdn(self):
        self.assertIn('data-diagram-fallback="cdn"', self.TEMPLATE_TEXT.splitlines()[1])


if __name__ == "__main__":
    unittest.main()
