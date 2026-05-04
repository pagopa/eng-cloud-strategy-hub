#!/usr/bin/env python3
"""Generate a semantic-release configuration file for the internal wrapper.

Dependency decision note
- Candidates: stdlib argparse/json/os/pathlib, click, pydantic
- Final choice: stdlib argparse/json/os/pathlib
- Why: the wrapper only needs deterministic JSON validation and file output.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Sequence

ENVIRONMENT_DEFAULTS = {
    "output": "RELEASERC_OUTPUT_PATH",
    "branches": "SEMANTIC_BRANCHES_INPUT",
    "tag_format": "TAG_FORMAT_INPUT",
    "preset": "PRESET_INPUT",
    "changelog_file": "CHANGELOG_FILE_INPUT",
    "git_author_name": "GIT_AUTHOR_NAME_INPUT",
    "git_author_email": "GIT_AUTHOR_EMAIL_INPUT",
    "release_rules": "RELEASE_RULES_INPUT",
    "debug": "DEBUG_INPUT",
}


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    if argv == []:
        return args_from_environment()

    parser = argparse.ArgumentParser(
        description="Generate a .releaserc.json file for the semantic-release composite action."
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output path for the generated .releaserc.json file.",
    )
    parser.add_argument(
        "--branches", required=True, help="semantic-release branches JSON."
    )
    parser.add_argument(
        "--tag-format", required=True, help="semantic-release tag format."
    )
    parser.add_argument("--preset", required=True, help="Conventional commit preset.")
    parser.add_argument("--changelog-file", required=True, help="Changelog file path.")
    parser.add_argument("--git-author-name", required=True, help="Git author name.")
    parser.add_argument("--git-author-email", required=True, help="Git author email.")
    parser.add_argument(
        "--release-rules", required=True, help="semantic-release releaseRules JSON."
    )
    parser.add_argument(
        "--debug",
        required=True,
        choices=["true", "false"],
        help="Print generated config.",
    )
    return parser.parse_args(argv)


def args_from_environment() -> argparse.Namespace:
    values: dict[str, str] = {}
    missing_names: list[str] = []

    for field_name, environment_name in ENVIRONMENT_DEFAULTS.items():
        value = os.environ.get(environment_name, "")
        if not value:
            missing_names.append(environment_name)
        values[field_name] = value

    if missing_names:
        missing = ", ".join(missing_names)
        raise ValueError(f"Missing required environment variables: {missing}.")

    return argparse.Namespace(**values)


def fail(message: str) -> int:
    print(f"❌ {message}", file=sys.stderr)
    return 1


def parse_json_array(raw_value: str, field_name: str) -> list[Any]:
    try:
        parsed = json.loads(raw_value)
    except json.JSONDecodeError as error:
        raise ValueError(f"{field_name} must be valid JSON: {error.msg}") from error

    if not isinstance(parsed, list):
        raise ValueError(f"{field_name} must be a JSON array.")

    return parsed


def build_config(args: argparse.Namespace) -> dict[str, Any]:
    branches = parse_json_array(args.branches, "branches")
    release_rules = parse_json_array(args.release_rules, "release_rules")

    if not args.tag_format.strip():
        raise ValueError("tag_format must not be empty.")
    if not args.preset.strip():
        raise ValueError("preset must not be empty.")
    if not args.changelog_file.strip():
        raise ValueError("changelog_file must not be empty.")
    if not args.git_author_name.strip():
        raise ValueError("git_author_name must not be empty.")
    if not args.git_author_email.strip():
        raise ValueError("git_author_email must not be empty.")

    return {
        "branches": branches,
        "tagFormat": args.tag_format,
        "plugins": [
            [
                "@semantic-release/commit-analyzer",
                {
                    "preset": args.preset,
                    "releaseRules": release_rules,
                },
            ],
            [
                "@semantic-release/release-notes-generator",
                {
                    "preset": args.preset,
                },
            ],
            [
                "@semantic-release/changelog",
                {
                    "changelogFile": args.changelog_file,
                },
            ],
            [
                "@semantic-release/git",
                {
                    "assets": [args.changelog_file],
                    "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}",
                },
            ],
            "@semantic-release/github",
        ],
    }


def write_config(output_path: Path, config: dict[str, Any]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = parse_args(sys.argv[1:] if argv is None else argv)
        output_path = Path(args.output)

        print(f"ℹ️  Generating semantic-release config at {output_path}")
        config = build_config(args)
    except ValueError as error:
        return fail(str(error))

    write_config(output_path, config)

    if args.debug == "true":
        print("ℹ️  Generated .releaserc.json content:")
        print(json.dumps(config, indent=2))

    print(f"✅ Wrote semantic-release config to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
