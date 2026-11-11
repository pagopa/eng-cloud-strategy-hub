"""Shared, read-only HTML contract and lossless slot editing."""

import hashlib
import html
import re
import tempfile
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

BUNDLE = Path(__file__).resolve().parents[1]
TEMPLATE = BUNDLE / "assets/template.html"
SEVERITIES = ("blocker", "important", "improvement", "note")
EVIDENCE = ("verified", "reproduced", "documented", "unverified")
LABELS = {
    "it": ("Bloccante", "Importante", "Miglioramento", "Nota"),
    "en": ("Blocker", "Important", "Improvement", "Note"),
}
VOID = set(
    "area base br col embed hr img input link meta param source track wbr".split()
)


@dataclass
class Node:
    tag: str
    attrs: dict[str, str]
    start: int
    open_end: int
    end: int
    close_start: int
    parent: "Node | None" = None
    children: list["Node | str"] = field(default_factory=list)

    @property
    def text(self) -> str:
        return "".join(
            c.text if isinstance(c, Node) else c for c in self.children
        ).strip()

    def select(self, key: str, value: str | None = None) -> list["Node"]:
        result = []
        for child in self.children:
            if isinstance(child, Node):
                if key in child.attrs and (value is None or child.attrs[key] == value):
                    result.append(child)
                result.extend(child.select(key, value))
        return result

    def tags(self, tag: str) -> list["Node"]:
        return [n for n in self.descendants() if n.tag == tag]

    def descendants(self) -> list["Node"]:
        result = []
        for child in self.children:
            if isinstance(child, Node):
                result.append(child)
                result.extend(child.descendants())
        return result


class Document(HTMLParser):
    def __init__(self, source: str):
        super().__init__(convert_charrefs=True)
        self.source = source
        self.offsets = [0]
        self.offsets.extend(m.end() for m in re.finditer("\n", source))
        self.nodes: list[Node] = []
        self.stack: list[Node] = []
        self.errors: list[str] = []
        self.feed(source)
        self.close()
        self.errors.extend(f"Unclosed <{n.tag}>" for n in self.stack)

    def position(self) -> int:
        line, column = self.getpos()
        return self.offsets[line - 1] + column

    def handle_starttag(self, tag, attrs):
        position = self.position()
        end = position + len(self.get_starttag_text())
        if len(attrs) != len(dict(attrs)):
            self.errors.append(f"Duplicate attribute on <{tag}>")
        node = Node(
            tag,
            {k: v or "" for k, v in attrs},
            position,
            end,
            end,
            end,
            self.stack[-1] if self.stack else None,
        )
        if node.parent:
            node.parent.children.append(node)
        self.nodes.append(node)
        if tag not in VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.stack.pop()

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1].tag != tag:
            self.errors.append(f"Unexpected </{tag}> at {self.getpos()}")
            return
        node = self.stack.pop()
        node.close_start = self.position()
        node.end = self.source.find(">", node.close_start) + 1

    def handle_data(self, data):
        if self.stack:
            self.stack[-1].children.append(data)

    def select(self, key: str, value: str | None = None) -> list[Node]:
        return [
            n
            for n in self.nodes
            if key in n.attrs and (value is None or n.attrs[key] == value)
        ]

    def one(self, key: str, value: str | None = None) -> Node:
        nodes = self.select(key, value)
        if len(nodes) != 1:
            raise ValueError(f"Expected one {key}={value!r}, found {len(nodes)}")
        return nodes[0]

    def raw(self, node: Node) -> str:
        return self.source[node.start : node.end]


def escape(value: str) -> str:
    return html.escape(value, quote=True)


def replace(source: str, edits: list[tuple[int, int, str]]) -> str:
    boundary = len(source)
    for start, end, content in sorted(edits, reverse=True):
        if not 0 <= start <= end <= boundary:
            raise ValueError("Overlapping or invalid slot replacements")
        source = source[:start] + content + source[end:]
        boundary = start
    return source


def atomic_write(path: Path, source: str) -> None:
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=".report-",
            suffix=".html",
            delete=False,
        ) as handle:
            temporary = Path(handle.name)
            handle.write(source)
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def invariant_errors(doc: Document) -> list[str]:
    template = Document(TEMPLATE.read_text(encoding="utf-8"))
    expected = template.select("data-invariant")
    failures = []
    for original in expected:
        key = original.attrs["data-invariant"]
        nodes = doc.select("data-invariant", key)
        if len(nodes) != 1:
            failures.append(f"Expected exactly one invariant block: {key}")
            continue

        def normalize(value: str) -> str:
            return value.replace("\r\n", "\n").replace("\r", "\n")

        actual = normalize(doc.raw(nodes[0])).encode()
        wanted = normalize(template.raw(original)).encode()
        if hashlib.sha256(actual).digest() != hashlib.sha256(wanted).digest():
            failures.append(f"Changed invariant block: {key}")
    if len(doc.select("data-invariant")) != len(expected):
        failures.append("Unknown, missing, or duplicated invariant blocks")
    return failures


def check(source: str, base: Path | None = None) -> list[dict[str, str]]:
    doc = Document(source)
    diagnostics: list[dict[str, str]] = []

    def report(
        rule: str, message: str, node: Node | None = None, severity: str = "error"
    ):
        diagnostics.append(
            {
                "rule": rule,
                "severity": severity,
                "message": message,
                "location": node.attrs.get("id", f"offset:{node.start}")
                if node
                else "document",
            }
        )

    def required_parts(node: Node, parts: tuple[str, ...], rule: str):
        for part in parts:
            found = node.select("data-part", part)
            if len(found) != 1 or not found[0].text or found[0].text in ("…", "..."):
                report(rule, f"Expected one non-empty {part}", node)

    for error in doc.errors:
        report("html-nesting", error)
    for error in invariant_errors(doc):
        report("invariant", error)
    roots = [n for n in doc.nodes if n.tag == "html"]
    if len(roots) != 1:
        report("html-root", "Expected one html root")
        return diagnostics
    root = roots[0]
    for key, allowed, rule in (
        ("data-report", ("review",), "html-root"),
        ("data-template-version", ("1",), "template-version"),
        (
            "data-accent",
            ("blue", "terracotta", "green", "violet", "graphite"),
            "accent",
        ),
        ("data-density", ("comfortable", "compact"), "density"),
        ("data-layout", ("atlante",), "layout"),
        ("lang", ("it", "en"), "language"),
        ("data-diagram-fallback", ("source", "cdn"), "diagram-fallback"),
    ):
        if root.attrs.get(key) not in allowed:
            report(rule, f"Unsupported or missing {key}", root)

    ids: dict[str, Node] = {}
    for node in doc.nodes:
        identifier = node.attrs.get("id")
        if identifier is not None:
            if not identifier or identifier in ids:
                report("duplicate-id", f"Empty or duplicated ID: {identifier}", node)
            ids[identifier] = node
        if node.tag in ("iframe", "object", "embed", "base", "form"):
            report("active-content", f"Unsupported active element: {node.tag}", node)
        if node.tag == "script" and node.attrs.get("data-invariant") != "script":
            report(
                "active-content", "Only the bundled invariant script is allowed", node
            )
        for name, value in node.attrs.items():
            if name.startswith("on") or (
                name in ("href", "src", "xlink:href")
                and re.match(r"\s*(javascript|data|vbscript):", value, re.I)
            ):
                report("active-content", f"Unsafe attribute: {name}", node)
        href = node.attrs.get("href", "")
        if href.startswith("#") and unquote(href[1:]) not in {
            n.attrs["id"] for n in doc.nodes if "id" in n.attrs
        }:
            report("fragment-link", f"Unresolved fragment: {href}", node)
        elif href and not href.startswith("#") and base is not None:
            url = urlsplit(href)
            if (
                not url.scheme
                and not url.netloc
                and url.path
                and not (base / unquote(url.path)).is_file()
            ):
                report("file-link", f"Missing relative file: {url.path}", node)

    sections = doc.select("data-section")
    for section in ("summary", "findings-index", "findings", "evidence"):
        if len(doc.select("data-section", section)) != 1:
            report("section", f"Expected exactly one {section} section")
    order = {
        "summary": 0,
        "findings-index": 1,
        "recommendations": 2,
        "custom": 3,
        "findings": 4,
        "notes": 5,
        "evidence": 6,
        "actions": 7,
    }
    sequence = [
        order[n.attrs["data-section"]]
        for n in sections
        if n.attrs["data-section"] in order
    ]
    if sequence != sorted(sequence):
        report("section-order", "Sections are out of contract order")
    for slot in ("header", "verdict", "analysis-disclaimer", "counts"):
        found = doc.select("data-slot", slot)
        if len(found) != 1 or not found[0].text:
            report("header", f"Expected one non-empty {slot}")
    if doc.select("data-pending"):
        report("content-pending", "Replace all pending scaffold content")
    for recommendations in doc.select("data-section", "recommendations"):
        if not recommendations.select("data-recommendation"):
            report(
                "empty-recommendations",
                "Recommendations section needs at least one recommendation",
                recommendations,
            )

    findings = doc.select("data-finding")
    counts = dict.fromkeys(SEVERITIES, 0)
    identities = set()
    native_adapter = {
        "BLOCKER": "blocker",
        "IMPORTANT": "important",
        "SUGGESTION": "improvement",
    }
    approved_adapters = {}
    for table in doc.select("data-severity-adapter"):
        if table.attrs.get("data-approved") != "true":
            report(
                "severity-adapter",
                "Custom severity adapters require explicit user approval",
                table,
            )
            continue
        for row in table.select("data-adapter-source"):
            original = row.attrs["data-adapter-source"]
            target = row.attrs.get("data-adapter-target")
            if (
                not original
                or target not in SEVERITIES
                or original in approved_adapters
            ):
                report("severity-adapter", "Invalid or duplicated adapter entry", row)
            else:
                approved_adapters[original] = target
    for finding in findings:
        severity = finding.attrs.get("data-severity", "")
        original = finding.attrs.get("data-source-severity", "")
        if severity != "note":
            expected = native_adapter.get(original, approved_adapters.get(original))
            if expected != severity:
                report(
                    "severity-adapter",
                    "Unapproved or inconsistent source severity projection",
                    finding,
                )
        if severity not in counts:
            report("severity", f"Unsupported severity: {severity}", finding)
        else:
            counts[severity] += 1
        if finding.attrs.get("data-evidence") not in EVIDENCE:
            report(
                "evidence-state",
                "Evidence must describe provenance, not applicability",
                finding,
            )
        identity = tuple(
            finding.attrs.get(k, "") for k in ("data-source-review", "data-source-id")
        )
        if all(identity) and identity in identities:
            report("source-identity", "Duplicated source review/ID pair", finding)
        identities.add(identity)
        for key in ("data-source-review", "data-source-id", "data-source-severity"):
            if not finding.attrs.get(key):
                report("source-metadata", f"Missing {key}", finding)
        metadata = finding.select("data-part", "source-metadata")
        values = [
            finding.attrs.get(k, "")
            for k in (
                "data-source-review",
                "data-source-id",
                "data-source-severity",
                "data-confidence",
            )
        ]
        if len(metadata) != 1 or any(v and v not in metadata[0].text for v in values):
            report(
                "source-metadata",
                "Source identity, severity and supplied confidence must be visible",
                finding,
            )
        required_parts(finding, ("problem", "sources"), "finding-part")
        required_parts(
            finding,
            ("indication",) if severity == "note" else ("example", "fix", "action"),
            "finding-part",
        )
        parent = finding.parent
        while parent and "data-section" not in parent.attrs:
            parent = parent.parent
        expected = "notes" if severity == "note" else "findings"
        if parent is None or parent.attrs.get("data-section") != expected:
            report("note-placement", f"Finding belongs in {expected}", finding)
        if finding.attrs.get("data-conditional") == "true":
            required_parts(finding, ("conditions",), "conditions")
        title = finding.tags("h3")
        if len(title) != 1 or not title[0].text:
            report("finding-title", "Expected one non-empty finding h3", finding)
    if not findings:
        section = doc.select("data-section", "findings")
        if not section or section[0].attrs.get("data-zero-findings") != "true":
            report(
                "zero-findings",
                "An empty report requires an explicit zero-findings source result",
            )
    elif any(
        n.attrs.get("data-zero-findings") == "true"
        for n in doc.select("data-section", "findings")
    ):
        report(
            "zero-findings",
            "Explicit zero finding result conflicts with supplied findings",
        )
    for severity, expected in counts.items():
        nodes = doc.select("data-count", severity)
        number_nodes = (
            [n for n in nodes[0].descendants() if n.attrs.get("class") == "n"]
            if len(nodes) == 1
            else []
        )
        numbers = [n.text for n in number_nodes]
        if numbers != [str(expected)]:
            report("count", f"Expected one {severity} count of {expected}")
    if len(doc.select("data-count")) != 4:
        report("count", "Expected exactly four severity counts")

    rows = doc.select("data-row")
    for finding in findings:
        linked = [
            r
            for r in rows
            if any(
                a.attrs.get("href") == "#" + finding.attrs.get("id", "")
                for a in r.tags("a")
            )
        ]
        expected = 0 if finding.attrs.get("data-severity") == "note" else 1
        if len(linked) != expected:
            report(
                "index-coverage", f"Expected {expected} index row for finding", finding
            )
    for row in rows:
        targets = [
            ids.get(a.attrs.get("href", "")[1:])
            for a in row.tags("a")
            if a.attrs.get("href", "").startswith("#")
        ]
        if (
            len(targets) != 1
            or targets[0] is None
            or "data-finding" not in targets[0].attrs
        ):
            report("index-coverage", "Index row must link to exactly one finding", row)
        elif (
            targets[0].attrs.get("data-severity") == "note"
            or targets[0].attrs.get("data-severity") != row.attrs["data-row"]
        ):
            report("index-severity", "Index severity differs from its finding", row)
        required_parts(row, ("action",), "index-action")

    for recommendation in doc.select("data-recommendation"):
        required_parts(
            recommendation,
            ("why", "how", "benefits", "conclusion"),
            "recommendation-part",
        )
        if not recommendation.tags("header"):
            report(
                "recommendation-part", "Missing recommendation header", recommendation
            )
        conclusion = recommendation.select("data-part", "conclusion")
        if conclusion and conclusion[0].tag != "footer":
            report(
                "recommendation-part",
                "Recommendation conclusion must be a footer",
                recommendation,
            )
        refs = recommendation.attrs.get("data-refs", "").split()
        if not refs or any(
            ref not in ids or "data-finding" not in ids[ref].attrs for ref in refs
        ):
            report(
                "recommendation-reference",
                "References must resolve to source findings",
                recommendation,
            )
        if recommendation.attrs.get(
            "data-structural"
        ) == "true" and not recommendation.select("data-part", "before-after"):
            report(
                "before-after",
                "Structural proposal needs a before/after comparison",
                recommendation,
            )
    for comparison in doc.select("data-part", "before-after"):
        if any(
            len(comparison.select("data-side", side)) != 1
            for side in ("before", "after")
        ):
            report(
                "before-after", "Expected one before and one after figure", comparison
            )
    for diagram in doc.select("data-diagram"):
        containers = [
            n for n in diagram.descendants() if n.attrs.get("class") == "diagram"
        ]
        if (
            len(containers) != 1
            or containers[0].attrs.get("role") != "img"
            or not containers[0].attrs.get("aria-label")
            or not diagram.tags("figcaption")
        ):
            report(
                "diagram-accessibility",
                "Diagram needs a caption and labelled image container",
                diagram,
            )
        sources = [
            n
            for n in diagram.tags("pre")
            if "mermaid-source" in n.attrs.get("class", "").split()
        ]
        if len(sources) != 1 or not all(
            re.search(rf"\b{part}\s*:\s*\S", sources[0].text)
            for part in ("accTitle", "accDescr")
        ):
            report("diagram-source", "Expected an accessible Mermaid source", diagram)
        elif re.search(
            r"(?m)^\s*(style|classDef|linkStyle)\b|%%\{|init\s*:", sources[0].text
        ):
            report("diagram-theme", "Diagram sources must be theme-neutral", diagram)

    checks = doc.select("data-check")
    if not checks:
        report("checks", "Record execution evidence or its explicit absence")
    for check_node in checks:
        if not check_node.attrs.get("id"):
            report("check-anchor", "Each check needs a unique anchor", check_node)
        if check_node.attrs.get("data-status") not in (
            "passed",
            "failed",
            "not-run",
            "blocked",
        ):
            report("check-status", "Unsupported or missing check status", check_node)
        required_parts(check_node, ("check-command", "check-result"), "check-part")
        if not any(
            n.attrs.get("data-section") == "evidence" and check_node in n.descendants()
            for n in sections
        ):
            report(
                "check-placement", "Checks belong in the evidence section", check_node
            )
    if counts["blocker"] or counts["important"]:
        actions = doc.select("data-section", "actions")
        if len(actions) != 1 or not actions[0].tags("li"):
            report(
                "actions", "Important findings require a source-backed order of work"
            )
    for node in doc.nodes:
        if node.tag == "p" and len(node.text.split()) > 120:
            report("long-prose", "Paragraph exceeds 120 words", node, "warning")
        if node.tag in ("p", "h1", "h2", "h3") and re.search(
            r"\b(caro collega|ai colleghi|da portare alla discussione)\b",
            node.text,
            re.I,
        ):
            report("tone", "Conversational framing in technical prose", node, "warning")
        ancestor = node
        in_code = False
        while ancestor:
            if ancestor.tag in ("pre", "code", "script", "style", "svg"):
                in_code = True
                break
            ancestor = ancestor.parent
        own_text = "".join(c for c in node.children if isinstance(c, str)).strip()
        if not in_code and re.search(r"[\U0001f300-\U0001faff\u2600-\u27bf]", own_text):
            valid = (
                node.attrs.get("class") == "emo"
                and node.attrs.get("aria-hidden") == "true"
                and own_text in ("🔍", "🛠️", "✅", "⚖️")
                and node.parent is not None
                and node.parent.tag == "dt"
            )
            if not valid:
                report(
                    "decorative-emoji",
                    "Emoji belong only in the four hidden part-label markers",
                    node,
                    "warning",
                )
        if "eyebrow" in node.attrs.get("class", "").split():
            report("eyebrow", "Avoid decorative labels above headings", node, "warning")
        if node.tag == "style" and "data-invariant" not in node.attrs:
            if re.search(
                r"border-(?:left|right|inline-start|inline-end)\s*:\s*(?:[2-9]\d*|1\d+)(?:\.\d+)?px",
                node.text,
            ):
                report(
                    "side-border", "Avoid thick colored side borders", node, "warning"
                )
    if not doc.errors and not invariant_errors(doc):
        from derive_report import derive

        try:
            derived = derive(source)
        except (ValueError, KeyError) as error:
            report("derived-content", f"Cannot derive report fields: {error}")
        else:
            if derived != source:
                report(
                    "derived-content",
                    "Counts, navigation, filters or index are stale; run derive_report.py",
                )
    return diagnostics
