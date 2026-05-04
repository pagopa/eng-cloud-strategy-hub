#!/usr/bin/env python3
"""Validate inputs for the semantic-release composite action.

Dependency decision note
- Candidates: stdlib os, click, pydantic
- Final choice: stdlib os
- Why: the action only needs deterministic scalar input validation.
"""

from __future__ import annotations

import os
import sys
from collections.abc import Mapping
from typing import Sequence

BOOLEAN_FIELDS = ("CHECKOUT_INPUT", "DEBUG_INPUT")
REQUIRED_FIELDS = (
    "GITHUB_TOKEN_INPUT",
    "SEMANTIC_VERSION_INPUT",
    "TAG_FORMAT_INPUT",
    "CHANGELOG_FILE_INPUT",
)


def fail(message: str) -> int:
    print(f"❌ {message}", file=sys.stderr)
    return 1


def validate_bool(environment: Mapping[str, str], name: str) -> None:
    value = environment.get(name, "")
    if value not in {"true", "false"}:
        raise ValueError(f"{name} must be 'true' or 'false'.")


def validate_inputs(environment: Mapping[str, str]) -> None:
    for name in REQUIRED_FIELDS:
        if not environment.get(name, ""):
            raise ValueError(f"{name} must not be empty.")

    for name in BOOLEAN_FIELDS:
        validate_bool(environment, name)


def main(argv: Sequence[str] | None = None) -> int:
    _ = argv
    try:
        validate_inputs(os.environ)
    except ValueError as error:
        return fail(str(error))

    print("✅ semantic-release wrapper inputs are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
