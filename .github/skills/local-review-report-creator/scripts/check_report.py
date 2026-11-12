"""Validate a report without modifying it."""

import argparse
import json
import sys
from pathlib import Path

from report_contract import check


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args()
    try:
        diagnostics = check(
            args.report.read_text(encoding="utf-8"), base=args.report.parent
        )
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Cannot check report: {error}", file=sys.stderr)
        return 1
    errors = sum(d["severity"] == "error" for d in diagnostics)
    warnings = len(diagnostics) - errors
    if args.format == "json":
        print(
            json.dumps(
                {"errors": errors, "warnings": warnings, "diagnostics": diagnostics},
                ensure_ascii=False,
            )
        )
    else:
        for diagnostic in diagnostics:
            print("{severity}: {rule} [{location}]: {message}".format(**diagnostic))
        print(f"{errors} error(s), {warnings} warning(s)")
    return int(errors > 0)


if __name__ == "__main__":
    sys.exit(main())
