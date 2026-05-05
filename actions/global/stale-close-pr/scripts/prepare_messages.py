#!/usr/bin/env python3
"""Prepare messages and validate inputs for the stale-close-pr composite action.

Dependency decision note
- Candidates: stdlib os/pathlib/uuid, click, pydantic
- Final choice: stdlib os/pathlib/uuid
- Why: the action only needs scalar validation and GitHub output formatting.
"""

from __future__ import annotations

import os
import sys
import uuid
from collections.abc import Mapping
from pathlib import Path

BOOLEAN_FIELDS = (
    "EXEMPT_DRAFT_PR_INPUT",
    "REMOVE_STALE_WHEN_UPDATED_INPUT",
    "ASCENDING_INPUT",
    "DELETE_BRANCH_INPUT",
)


def fail(message: str) -> int:
    print(f"❌ {message}", file=sys.stderr)
    return 1


def validate_bool(environment: Mapping[str, str], name: str) -> None:
    value = environment.get(name, "")
    if value not in {"true", "false"}:
        raise ValueError(f"{name} must be 'true' or 'false'.")


def parse_integer(environment: Mapping[str, str], name: str, minimum: int) -> int:
    raw_value = environment.get(name, "")
    try:
        value = int(raw_value)
    except ValueError as error:
        raise ValueError(f"{name} must be an integer.") from error

    if value < minimum:
        raise ValueError(f"{name} must be greater than or equal to {minimum}.")

    return value


def validate_inputs(environment: Mapping[str, str]) -> tuple[int, int]:
    days_before_stale = parse_integer(environment, "DAYS_BEFORE_STALE_INPUT", -1)
    days_before_close = parse_integer(environment, "DAYS_BEFORE_CLOSE_INPUT", -1)
    parse_integer(environment, "OPERATIONS_PER_RUN_INPUT", 1)

    for name in BOOLEAN_FIELDS:
        validate_bool(environment, name)

    return days_before_stale, days_before_close


def build_stale_message(
    custom_message: str, days_before_stale: int, days_before_close: int
) -> str:
    if custom_message:
        return custom_message

    if days_before_close == -1:
        return (
            "This pull request has been automatically marked as stale because it has not had any activity "
            f"for {days_before_stale} days.\n"
            "It will not be automatically closed.\n\n"
            "If you believe this PR should remain open, please add a comment or push new commits to keep it active.\n\n"
            "Thank you for your contribution! 🙏"
        )

    return (
        "This pull request has been automatically marked as stale because it has not had any activity "
        f"for {days_before_stale} days.\n"
        f"It will be closed in {days_before_close} days if no further activity occurs.\n\n"
        "If you believe this PR should remain open, please add a comment or push new commits to keep it active.\n\n"
        "Thank you for your contribution! 🙏"
    )


def build_close_message(custom_message: str, days_before_close: int) -> str:
    if custom_message:
        return custom_message

    if days_before_close == -1:
        return "Automatic close is disabled for this pull request."

    return (
        f"This pull request has been automatically closed due to inactivity after {days_before_close} days.\n\n"
        "If you would like to continue working on this, please reopen the PR and add new commits.\n\n"
        "Thank you for your contribution! 🙏"
    )


def write_multiline_output(output_path: Path, key: str, value: str) -> None:
    delimiter = f"EOF_{uuid.uuid4().hex}"
    with output_path.open("a", encoding="utf-8") as output_file:
        output_file.write(f"{key}<<{delimiter}\n{value}\n{delimiter}\n")


def main() -> int:
    environment = os.environ

    try:
        output_path_raw = environment.get("GITHUB_OUTPUT", "")
        if not output_path_raw:
            raise ValueError("GITHUB_OUTPUT is required.")

        days_before_stale, days_before_close = validate_inputs(environment)
        stale_message = build_stale_message(
            environment.get("STALE_PR_MESSAGE_INPUT", ""),
            days_before_stale,
            days_before_close,
        )
        close_message = build_close_message(
            environment.get("CLOSE_PR_MESSAGE_INPUT", ""),
            days_before_close,
        )

        output_path = Path(output_path_raw)
        write_multiline_output(output_path, "stale", stale_message)
        write_multiline_output(output_path, "close", close_message)
    except ValueError as error:
        return fail(str(error))

    print("✅ stale-close-pr inputs and messages are ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
