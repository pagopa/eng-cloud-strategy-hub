"""Embed locally rendered SVG; preserve every Mermaid source."""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from report_contract import Document, atomic_write, invariant_errors, replace


def safe_svg(source: str, prefix: str) -> str:
    if re.search(r"<!DOCTYPE|<!ENTITY", source, re.I):
        raise ValueError("SVG entities and doctypes are not allowed")
    try:
        root = ET.fromstring(source)
    except ET.ParseError as error:
        raise ValueError(f"Invalid SVG: {error}") from error
    if root.tag != "{http://www.w3.org/2000/svg}svg":
        raise ValueError("Expected an SVG namespace root")
    nodes = list(root.iter())
    ids = [node.attrib["id"] for node in nodes if "id" in node.attrib]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate SVG IDs")
    mapping = {identifier: f"{prefix}--{identifier}" for identifier in ids}
    for node in nodes:
        tag = node.tag.rsplit("}", 1)[-1].lower()
        if tag in (
            "script",
            "foreignobject",
            "iframe",
            "object",
            "embed",
            "a",
            "animate",
            "set",
            "image",
        ):
            raise ValueError(f"Unsafe SVG element: {tag}")
        for key, value in list(node.attrib.items()):
            local = key.rsplit("}", 1)[-1].lower()
            if local.startswith("on"):
                raise ValueError(f"Unsafe SVG event: {key}")
            if local in ("href", "src") and (
                not value.startswith("#") or value[1:] not in mapping
            ):
                raise ValueError("External or unresolved SVG reference")
            if re.search(r"@import|expression\s*\(|javascript:|data:", value, re.I):
                raise ValueError("Unsafe SVG attribute value")
            for url in re.findall(r"url\(\s*['\"]?([^)'\"\s]+)", value):
                if not url.startswith("#") or url[1:] not in mapping:
                    raise ValueError("External or unresolved SVG URL")
        if tag == "style":
            css = node.text or ""
            css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
            css = re.sub(
                r"@keyframes\s+(?:edge-animation-frame|dash)\s*\{\s*(?:from|to)\s*\{\s*stroke-dashoffset\s*:\s*0\s*;?\s*\}\s*\}",
                "",
                css,
            )
            css = re.sub(
                r"\banimation(?:-[a-z-]+)?\s*:[^;{}]*(?:;|(?=\}))", "", css, flags=re.I
            )
            node.text = css
            root_id = root.attrib.get("id", "")
            if not root_id or "\\" in css or "@" in css:
                raise ValueError(
                    "SVG styles need a root ID and no imports or CSS escapes"
                )
            rules = re.findall(r"([^{}]+)\{([^{}]*)\}", css)
            if re.sub(r"[^{}]+\{[^{}]*\}", "", css).strip():
                raise ValueError("Unsupported SVG CSS structure")
            prefix = "#" + root_id
            for selectors, _ in rules:
                for selector in selectors.split(","):
                    selector = selector.strip()
                    if not selector.startswith(prefix):
                        raise ValueError(
                            "SVG CSS selectors must be scoped to the SVG root"
                        )
                    tail = selector[len(prefix) :]
                    if tail and not tail.startswith((" ", "\t", "\n", ">")):
                        raise ValueError("SVG CSS selector escapes its root")
                    if tail.lstrip().startswith(("+", "~")):
                        raise ValueError("SVG CSS cannot target root siblings")
            if re.search(r"@import|expression\s*\(|javascript:|data:", css, re.I):
                raise ValueError("Unsafe SVG style")
            if any(
                not url.startswith("#") or url[1:] not in mapping
                for url in re.findall(r"url\(\s*['\"]?([^)'\"\s]+)", css)
            ):
                raise ValueError("External SVG CSS URL")
    for node in nodes:
        for key, value in list(node.attrib.items()):
            local = key.rsplit("}", 1)[-1].lower()
            if local == "id":
                node.set(key, mapping[value])
            elif local in ("href", "src"):
                node.set(key, "#" + mapping[value[1:]])
            elif local in ("aria-labelledby", "aria-describedby"):
                if any(identifier not in mapping for identifier in value.split()):
                    raise ValueError("Unresolved accessible SVG ID")
                node.set(key, " ".join(mapping[v] for v in value.split()))
            else:
                node.set(
                    key,
                    re.sub(
                        r"url\(\s*(['\"]?)#([^)'\"\s]+)\1\s*\)",
                        lambda m: f"url(#{mapping[m[2]]})",
                        value,
                    ),
                )
        if node.tag.rsplit("}", 1)[-1] == "style" and node.text:
            css = node.text
            for identifier in sorted(mapping, key=len, reverse=True):
                css = re.sub(
                    r"#" + re.escape(identifier) + r"(?![\w-])",
                    "#" + mapping[identifier],
                    css,
                )
            node.text = css
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    return ET.tostring(root, encoding="unicode")


def embed(source: str, diagrams: dict[str, str]) -> str:
    doc = Document(source)
    errors = doc.errors + invariant_errors(doc)
    if errors:
        raise ValueError("; ".join(errors))
    edits = []
    seen = set()
    for figure in doc.select("data-diagram"):
        identifier = figure.attrs.get("id", "")
        if (
            not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", identifier)
            or identifier in seen
        ):
            raise ValueError("Diagrams need distinct safe IDs before embedding")
        seen.add(identifier)
        if identifier in diagrams:
            containers = [
                n for n in figure.descendants() if n.attrs.get("class") == "diagram"
            ]
            if len(containers) != 1:
                raise ValueError(f"Expected one diagram container: {identifier}")
            container = containers[0]
            edits.append(
                (
                    container.open_end,
                    container.close_start,
                    safe_svg(diagrams[identifier], identifier),
                )
            )
    if set(diagrams) - seen:
        raise ValueError("SVG input has no matching diagram figure")
    return replace(source, edits)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument(
        "--svg-dir", type=Path, help="Local SVG files named after diagram IDs"
    )
    args = parser.parse_args()
    try:
        source = args.report.read_text(encoding="utf-8")
        doc = Document(source)
        figures = doc.select("data-diagram")
        diagrams = {}
        if args.svg_dir is not None:
            for figure in figures:
                identifier = figure.attrs.get("id", "")
                if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", identifier):
                    raise ValueError("Diagram IDs must be safe file stems")
                svg = args.svg_dir / f"{identifier}.svg"
                if not svg.is_file() or svg.is_symlink():
                    raise ValueError(f"Missing regular local SVG: {svg}")
                diagrams[identifier] = svg.read_text(encoding="utf-8")
        elif figures:
            renderer = shutil.which("mmdc")
            if renderer is None:
                print(
                    "warning: mmdc unavailable; no file changed. Use --svg-dir or retain the visible source fallback.",
                    file=sys.stderr,
                )
                return 0
            with tempfile.TemporaryDirectory(prefix="review-diagrams-") as directory:
                work = Path(directory)
                config = work / "config.json"
                config.write_text(
                    json.dumps(
                        {
                            "securityLevel": "strict",
                            "htmlLabels": False,
                            "flowchart": {"htmlLabels": False},
                        }
                    )
                )
                for number, figure in enumerate(figures):
                    sources = [
                        n
                        for n in figure.tags("pre")
                        if n.attrs.get("class") == "mermaid-source"
                    ]
                    if len(sources) != 1:
                        raise ValueError("Missing Mermaid source")
                    mmd, svg = work / f"{number}.mmd", work / f"{number}.svg"
                    mmd.write_text(sources[0].text, encoding="utf-8")
                    subprocess.run(
                        [renderer, "-i", str(mmd), "-o", str(svg), "-c", str(config)],
                        check=True,
                        timeout=120,
                        capture_output=True,
                        text=True,
                    )
                    diagrams[figure.attrs.get("id", "")] = svg.read_text(
                        encoding="utf-8"
                    )
        result = embed(source, diagrams)
        atomic_write(args.report, result)
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError) as error:
        print(f"Cannot embed diagrams: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        return 1
    print(f"Embedded {len(diagrams)} diagram(s): {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
