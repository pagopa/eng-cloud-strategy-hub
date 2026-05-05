#!/usr/bin/env python3
"""Validate inputs for the release-please composite action.

Dependency decision note
- Candidates: stdlib argparse/json/os/pathlib, click, pydantic
- Final choice: stdlib argparse/json/os/pathlib
- Why: validation is small, deterministic, and does not need external packages.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Sequence

BOOLEAN_FIELDS = (
    "CHECKOUT_INPUT",
    "AUTO_MERGE_INPUT",
    "SKIP_GITHUB_RELEASE_INPUT",
    "DEBUG_INPUT",
)
MERGE_METHODS = {"merge", "squash", "rebase"}


def fail(message: str) -> int:
    print(f"❌ {message}", file=sys.stderr)
    return 1


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate release-please wrapper inputs."
    )
    parser.add_argument(
        "--phase",
        choices=("wrapper", "files"),
        required=True,
        help="Validation phase to run.",
    )
    return parser.parse_args(argv)


def require_not_empty(environment: Mapping[str, str], name: str) -> None:
    if not environment.get(name, ""):
        raise ValueError(f"{name} must not be empty.")


def validate_bool(environment: Mapping[str, str], name: str) -> None:
    value = environment.get(name, "")
    if value not in {"true", "false"}:
        raise ValueError(f"{name} must be 'true' or 'false'.")


def validate_wrapper_inputs(environment: Mapping[str, str]) -> None:
    require_not_empty(environment, "GITHUB_TOKEN_INPUT")
    require_not_empty(environment, "TARGET_BRANCH_INPUT")

    for name in BOOLEAN_FIELDS:
        validate_bool(environment, name)

    merge_method = environment.get("MERGE_METHOD_INPUT", "")
    if merge_method not in MERGE_METHODS:
        raise ValueError("MERGE_METHOD_INPUT must be one of: merge, squash, rebase.")


def validate_json_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise ValueError(f"{label} file not found: {path}")

    try:
        json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(
            f"{label} file must be valid JSON: {path}: {error.msg}"
        ) from error


def resolve_workspace_file(
    environment: Mapping[str, str], raw_path: str, label: str
) -> Path:
    workspace = Path(environment.get("GITHUB_WORKSPACE", ".")).resolve()
    candidate = Path(raw_path)

    if candidate.is_absolute():
        raise ValueError(
            f"{label} file must use a repository-relative path: {raw_path}"
        )

    resolved = (workspace / candidate).resolve()
    try:
        resolved.relative_to(workspace)
    except ValueError as error:
        raise ValueError(
            f"{label} file must stay inside GITHUB_WORKSPACE: {raw_path}"
        ) from error

    return resolved


def validate_consumer_files(environment: Mapping[str, str]) -> None:
    config_file = environment.get("CONFIG_FILE_INPUT", "")
    manifest_file = environment.get("MANIFEST_FILE_INPUT", "")

    if not config_file:
        raise ValueError("CONFIG_FILE_INPUT must not be empty.")
    if not manifest_file:
        raise ValueError("MANIFEST_FILE_INPUT must not be empty.")

    resolved_config_file = resolve_workspace_file(
        environment, config_file, "release-please config"
    )
    resolved_manifest_file = resolve_workspace_file(
        environment, manifest_file, "release-please manifest"
    )

    validate_json_file(resolved_config_file, "release-please config")
    validate_json_file(resolved_manifest_file, "release-please manifest")

    if environment.get("DEBUG_INPUT") == "true":
        print(f"ℹ️  config_file={config_file}")
        print(f"ℹ️  manifest_file={manifest_file}")
        print(f"ℹ️  target_branch={environment.get('TARGET_BRANCH_INPUT', '')}")
        print(f"ℹ️  merge_method={environment.get('MERGE_METHOD_INPUT', '')}")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        if args.phase == "wrapper":
            validate_wrapper_inputs(os.environ)
        else:
            validate_consumer_files(os.environ)
    except ValueError as error:
        return fail(str(error))

    print(f"✅ release-please {args.phase} inputs are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
