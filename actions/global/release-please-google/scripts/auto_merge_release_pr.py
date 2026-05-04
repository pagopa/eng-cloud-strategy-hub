#!/usr/bin/env python3
"""Resolve release-please pull requests and optionally enable GitHub auto-merge.

Dependency decision note
- Candidates: stdlib json/os/subprocess, PyGithub, GitHub CLI wrappers
- Final choice: stdlib plus the runner-provided gh CLI
- Why: the action already depends on gh for GitHub operations and only needs small JSON transformations.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

MERGE_METHODS = {"merge", "squash", "rebase"}
PERMISSION_ERROR_PATTERN = re.compile(
    r"resource not accessible by integration|insufficient|permission|forbidden|403",
    re.IGNORECASE,
)
AUTO_MERGE_DISABLED_PATTERN = re.compile(
    r"auto-merge.*(disabled|not enabled)|enable auto-merge",
    re.IGNORECASE,
)
AUTO_MERGE_ALREADY_PATTERN = re.compile(
    r"already.*auto-merge|auto-merge.*already",
    re.IGNORECASE,
)
RELEASE_PLEASE_TITLE_PATTERN = re.compile(
    r"^\s*chore(?:\([^)\r\n]+\))?: release\b",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class ReleasePullRequest:
    number: int
    url: str
    title: str
    head_branch_name: str
    base_branch_name: str
    source: str
    author: str = ""

    def to_output(self) -> dict[str, Any]:
        output: dict[str, Any] = {
            "number": self.number,
            "url": self.url,
            "title": self.title,
            "headBranchName": self.head_branch_name,
            "baseBranchName": self.base_branch_name,
            "source": self.source,
        }
        if self.author:
            output["author"] = self.author
        return output


def log_info(message: str) -> None:
    print(f"ℹ️  {message}")


def log_success(message: str) -> None:
    print(f"✅ {message}")


def log_warn(message: str) -> None:
    print(f"⚠️  {message}")


def fail(message: str) -> int:
    print(f"❌ {message}", file=sys.stderr)
    return 1


def parse_json_payload(raw_value: str, default: Any) -> Any:
    if not raw_value:
        return default

    try:
        return json.loads(raw_value)
    except json.JSONDecodeError:
        return default


def read_string(item: Mapping[str, Any], *names: str) -> str:
    for name in names:
        value = item.get(name)
        if isinstance(value, str):
            return value
    return ""


def is_release_please_title(title: str) -> bool:
    return RELEASE_PLEASE_TITLE_PATTERN.search(title) is not None


def is_release_please_author(author_login: str) -> bool:
    login = author_login.lower()
    return "[bot]" in login or login.startswith("app/") or login == "github-actions"


def pr_url(server_url: str, repository: str, number: int) -> str:
    if not repository:
        return str(number)
    return f"{server_url.rstrip('/')}/{repository}/pull/{number}"


def release_pr_from_release_please_output(
    item: Mapping[str, Any],
    target_branch: str,
    server_url: str,
    repository: str,
) -> ReleasePullRequest | None:
    number = item.get("number")
    if not isinstance(number, int):
        return None

    head_branch = read_string(item, "headBranchName", "headRefName")
    base_branch = read_string(item, "baseBranchName", "baseRefName")
    title = read_string(item, "title")

    if not head_branch.startswith("release-please--"):
        return None
    if base_branch != target_branch:
        return None
    if not is_release_please_title(title):
        return None

    return ReleasePullRequest(
        number=number,
        url=read_string(item, "url") or pr_url(server_url, repository, number),
        title=title,
        head_branch_name=head_branch,
        base_branch_name=base_branch,
        source="release-please-output",
    )


def normalize_release_please_outputs(
    raw_pr: str,
    raw_prs: str,
    target_branch: str,
    server_url: str,
    repository: str,
) -> list[ReleasePullRequest]:
    payloads = parse_json_payload(raw_prs, [])
    single_pr = parse_json_payload(raw_pr, None)

    if not isinstance(payloads, list):
        payloads = []
    if isinstance(single_pr, dict):
        payloads.append(single_pr)

    normalized: list[ReleasePullRequest] = []
    seen_numbers: set[int] = set()

    for item in payloads:
        if not isinstance(item, dict):
            continue
        release_pr = release_pr_from_release_please_output(
            item, target_branch, server_url, repository
        )
        if release_pr is None or release_pr.number in seen_numbers:
            continue
        seen_numbers.add(release_pr.number)
        normalized.append(release_pr)

    return normalized


def gh_available() -> bool:
    return shutil.which("gh") is not None


def run_gh_json(args: Sequence[str]) -> Any:
    completed = subprocess.run(
        ["gh", *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            completed.stderr.strip() or completed.stdout.strip() or "gh command failed."
        )

    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"gh returned invalid JSON: {error.msg}") from error


def release_pr_from_gh_item(item: Mapping[str, Any]) -> ReleasePullRequest | None:
    author = item.get("author") or {}
    author_login = author.get("login", "") if isinstance(author, dict) else ""
    head_branch = read_string(item, "headRefName")
    title = read_string(item, "title")

    if not head_branch.startswith("release-please--"):
        return None
    if not is_release_please_title(title):
        return None
    if not is_release_please_author(author_login):
        return None

    number = item.get("number")
    if not isinstance(number, int):
        return None

    return ReleasePullRequest(
        number=number,
        url=read_string(item, "url"),
        title=title,
        head_branch_name=head_branch,
        base_branch_name=read_string(item, "baseRefName"),
        source="gh-fallback",
        author=author_login,
    )


def discover_release_please_prs(target_branch: str) -> list[ReleasePullRequest]:
    if not gh_available():
        raise RuntimeError(
            "gh CLI is required to discover release-please pull requests."
        )

    items = run_gh_json(
        [
            "pr",
            "list",
            "--state",
            "open",
            "--base",
            target_branch,
            "--json",
            "number,title,url,headRefName,baseRefName,author",
        ]
    )

    if not isinstance(items, list):
        raise RuntimeError("gh pr list returned an unexpected JSON payload.")

    normalized: list[ReleasePullRequest] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        release_pr = release_pr_from_gh_item(item)
        if release_pr is not None:
            normalized.append(release_pr)

    return normalized


def output_json(release_prs: list[ReleasePullRequest]) -> str:
    return json.dumps([item.to_output() for item in release_prs], separators=(",", ":"))


def write_output(output_path: Path, key: str, value: str) -> None:
    with output_path.open("a", encoding="utf-8") as output_file:
        output_file.write(f"{key}={value}\n")


def emit_pr_outputs(
    output_path: Path, release_prs: list[ReleasePullRequest], auto_merge: str
) -> None:
    first_pr_url = release_prs[0].url if release_prs else ""
    write_output(output_path, "pr", first_pr_url)
    write_output(output_path, "prs", output_json(release_prs))
    write_output(output_path, "auto_merge_enabled", auto_merge)


def classify_gh_merge_error(pr_number: int, error_output: str) -> str:
    if PERMISSION_ERROR_PATTERN.search(error_output):
        return f"The provided github_token does not have enough permissions to enable auto-merge for PR #{pr_number}."
    if AUTO_MERGE_DISABLED_PATTERN.search(error_output):
        return f"Repository auto-merge is not enabled or is unavailable for PR #{pr_number}."
    return f"gh pr merge --auto failed for PR #{pr_number}: {error_output}"


def enable_auto_merge(release_prs: list[ReleasePullRequest], merge_method: str) -> None:
    if not gh_available():
        raise RuntimeError("gh CLI is required when auto_merge is true.")

    for release_pr in release_prs:
        completed = subprocess.run(
            ["gh", "pr", "merge", release_pr.url, "--auto", f"--{merge_method}"],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode == 0:
            log_success(
                f"Enabled auto-merge for PR #{release_pr.number} with '{merge_method}'."
            )
            continue

        error_output = completed.stderr.strip() or completed.stdout.strip()
        if AUTO_MERGE_ALREADY_PATTERN.search(error_output):
            log_warn(f"Auto-merge was already enabled for PR #{release_pr.number}.")
            continue

        raise RuntimeError(classify_gh_merge_error(release_pr.number, error_output))


def require_env(environment: Mapping[str, str], name: str) -> str:
    value = environment.get(name, "")
    if not value:
        raise ValueError(f"{name} is required.")
    return value


def validate_bool_like(environment: Mapping[str, str], name: str) -> str:
    value = require_env(environment, name)
    if value not in {"true", "false"}:
        raise ValueError(f"{name} must be 'true' or 'false'.")
    return value


def validate_merge_method(environment: Mapping[str, str]) -> str:
    merge_method = require_env(environment, "RP_MERGE_METHOD")
    if merge_method not in MERGE_METHODS:
        raise ValueError("RP_MERGE_METHOD must be one of: merge, squash, rebase.")
    return merge_method


def resolve_release_prs(
    environment: Mapping[str, str], allow_fallback: bool
) -> list[ReleasePullRequest]:
    target_branch = require_env(environment, "RP_TARGET_BRANCH")
    release_prs = normalize_release_please_outputs(
        raw_pr=environment.get("RP_PR", ""),
        raw_prs=environment.get("RP_PRS", ""),
        target_branch=target_branch,
        server_url=environment.get("GITHUB_SERVER_URL", "https://github.com"),
        repository=environment.get("GITHUB_REPOSITORY", ""),
    )

    if environment.get("RP_DEBUG") == "true":
        log_info(f"release-please outputs candidate PRs: {output_json(release_prs)}")

    if release_prs:
        return release_prs

    if not allow_fallback:
        return []

    if not gh_available() and environment.get("RP_AUTO_MERGE") == "false":
        log_warn(
            "gh CLI is not available; skipping fallback PR discovery because auto_merge is disabled."
        )
        return []

    release_prs = discover_release_please_prs(target_branch)
    if environment.get("RP_DEBUG") == "true":
        log_info(f"gh fallback candidate PRs: {output_json(release_prs)}")
    return release_prs


def main() -> int:
    environment = os.environ

    try:
        require_env(environment, "GITHUB_TOKEN")
        output_path = Path(require_env(environment, "GITHUB_OUTPUT"))
        auto_merge = validate_bool_like(environment, "RP_AUTO_MERGE")
        validate_bool_like(environment, "RP_DEBUG")
        merge_method = validate_merge_method(environment)
        release_created = environment.get("RP_RELEASE_CREATED", "false")
        release_prs = resolve_release_prs(
            environment, allow_fallback=release_created != "true"
        )

        emit_pr_outputs(output_path, release_prs, auto_merge)

        if not release_prs:
            if release_created == "true":
                log_success(
                    "release-please created a release; no open release PR is expected."
                )
                return 0
            if auto_merge == "true":
                return fail(
                    f"No open release-please pull request was found for target branch "
                    f"'{environment['RP_TARGET_BRANCH']}'."
                )

            log_info("No release-please pull request was resolved.")
            return 0

        if auto_merge == "false":
            log_info(
                "Auto-merge is disabled. Release PRs were resolved without merge operations."
            )
            return 0

        enable_auto_merge(release_prs, merge_method)
    except (RuntimeError, ValueError) as error:
        return fail(str(error))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
