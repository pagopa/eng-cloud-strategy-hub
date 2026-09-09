#!/usr/bin/env python3
"""Generate a user-friendly GitHub Actions step summary for release-please.

Dependency decision note
- Candidates: stdlib json/os/pathlib/sys
- Final choice: stdlib
- Why: GitHub step summary only requires writing Markdown directly to GITHUB_STEP_SUMMARY.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Mapping

OUTCOME_KEYS = (
    "RP_STEP_OUTCOME",
    "RP_VALIDATE_WRAPPER_OUTCOME",
    "RP_CHECKOUT_STRATEGY_OUTCOME",
    "RP_CHECKOUT_OUTCOME",
    "RP_VALIDATE_FILES_OUTCOME",
    "RP_RELEASE_OUTCOME",
    "RP_RELEASE_PR_OUTCOME",
)
MAX_FAILURE_LOG_CHARS = 20_000
LOG_REDACTION_PATTERNS = (
    (re.compile(r"(authorization\s*:\s*bearer\s+)[^\s]+", re.IGNORECASE), r"\1[REDACTED]"),
    (re.compile(r"(x-access-token\s*:\s*)[^\s]+", re.IGNORECASE), r"\1[REDACTED]"),
    (re.compile(r"\b(?:gh[pousr]_\w+|github_pat_[A-Za-z0-9_=-]+)\b"), "[REDACTED]"),
)


def parse_json_safely(raw_value: str, default: Any) -> Any:
    if not raw_value:
        return default
    try:
        return json.loads(raw_value)
    except Exception:
        return default


def aggregate_step_outcome(environment: Mapping[str, str]) -> str:
    outcomes = {
        environment.get(key, "").strip()
        for key in OUTCOME_KEYS
        if environment.get(key, "").strip()
    }

    if "failure" in outcomes:
        return "failure"
    if "timed_out" in outcomes:
        return "timed_out"
    if "cancelled" in outcomes:
        return "cancelled"
    return "success"


def is_true(value: Any) -> bool:
    return str(value).strip().lower() == "true"


def string_value(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def release_details(environment: Mapping[str, str]) -> list[dict[str, str]]:
    paths_released = parse_json_safely(
        environment.get("RP_PATHS_RELEASED", "[]"), []
    )
    if not isinstance(paths_released, list):
        paths_released = []

    release_outputs = parse_json_safely(
        environment.get("RP_RELEASE_OUTPUTS_JSON", "{}"), {}
    )
    if not isinstance(release_outputs, dict):
        release_outputs = {}

    details: list[dict[str, str]] = []
    for path in paths_released:
        if not isinstance(path, str):
            continue

        prefix = "" if path in {"", "."} else f"{path}--"
        if prefix:
            values = {
                key[len(prefix):]: value
                for key, value in release_outputs.items()
                if isinstance(key, str) and key.startswith(prefix)
            }
        else:
            values = release_outputs

        release_created = values.get("release_created")
        if release_created is not None and not is_true(release_created):
            continue

        details.append({
            "path": path or ".",
            "version": string_value(values.get("version")),
            "tag_name": string_value(values.get("tag_name")),
            "html_url": string_value(values.get("html_url")),
        })

    if details:
        return details

    if not is_true(environment.get("RP_RELEASE_CREATED")) and not is_true(
        environment.get("RP_RELEASES_CREATED")
    ):
        return []

    fallback_paths = [
        path for path in paths_released if isinstance(path, str) and path
    ] or ["."]
    fallback_version = environment.get("RP_VERSION", "").strip()
    fallback_tag = environment.get("RP_TAG_NAME", "").strip()
    fallback_url = environment.get("RP_HTML_URL", "").strip()
    for path in fallback_paths:
        details.append({
            "path": path,
            "version": fallback_version if len(fallback_paths) == 1 else "",
            "tag_name": fallback_tag if len(fallback_paths) == 1 else "",
            "html_url": fallback_url if len(fallback_paths) == 1 else "",
        })
    return details


def markdown_code(value: str) -> str:
    if not value:
        return "—"
    safe_value = value.replace("`", "'").replace("|", "\\|").replace("\n", " ")
    return f"`{safe_value}`"


def render_release_details(releases: list[dict[str, str]]) -> list[str]:
    if not releases:
        return []

    lines = [
        f"### 📦 Releases generated ({len(releases)})",
        "",
        "| Package | Version | Tag | GitHub Release |",
        "| :--- | :--- | :--- | :--- |",
    ]
    for release in releases:
        release_url = release["html_url"]
        release_link = (
            f"[View release]({release_url})"
            if release_url.startswith(("https://", "http://"))
            else "—"
        )
        lines.append(
            "| "
            f"{markdown_code(release['path'])} | "
            f"{markdown_code(release['version'])} | "
            f"{markdown_code(release['tag_name'])} | "
            f"{release_link} |"
        )
    lines.append("")
    return lines


def redact_log(log_content: str) -> str:
    redacted = log_content
    for pattern, replacement in LOG_REDACTION_PATTERNS:
        redacted = pattern.sub(replacement, redacted)
    return redacted.replace("```", "[triple-backtick]")


def read_failure_logs(environment: Mapping[str, str]) -> str:
    log_dir_value = environment.get("RP_LOG_DIR", "").strip()
    if not log_dir_value:
        return ""

    log_dir = Path(log_dir_value)
    if not log_dir.is_dir():
        return ""

    sections: list[str] = []
    for log_path in sorted(log_dir.glob("*.log")):
        try:
            content = log_path.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError):
            continue
        if not content:
            continue
        sections.append(
            f"### {log_path.stem}\n\n```text\n{redact_log(content)}\n```"
        )

    combined = "\n\n".join(sections)
    if len(combined) <= MAX_FAILURE_LOG_CHARS:
        return combined
    return (
        "[...failure log truncated to the last "
        f"{MAX_FAILURE_LOG_CHARS:,} characters...]\n\n"
        + combined[-MAX_FAILURE_LOG_CHARS:]
    )


def format_summary(environment: Mapping[str, str]) -> str:
    release_created = environment.get("RP_RELEASE_CREATED", "false") == "true"
    releases_created_flag = environment.get("RP_RELEASES_CREATED", "false") == "true"
    is_release_published = release_created or releases_created_flag

    prs_created = environment.get("RP_PRS_CREATED", "false") == "true"
    pr_url = environment.get("RP_PR", "").strip()
    tag_name = environment.get("RP_TAG_NAME", "").strip()
    target_branch = environment.get("RP_TARGET_BRANCH", "main")
    auto_merge = environment.get("RP_AUTO_MERGE", "false")
    merge_method = environment.get("RP_MERGE_METHOD", "squash")
    skip_github_release = environment.get("RP_SKIP_GITHUB_RELEASE", "false") == "true"
    publication_status = "disabled" if skip_github_release else "enabled"
    paths_released_raw = environment.get("RP_PATHS_RELEASED", "[]")
    paths_released = parse_json_safely(paths_released_raw, [])
    step_outcome = aggregate_step_outcome(environment)
    failure_reason = environment.get("RP_FAILURE_REASON", "").strip()
    releases = release_details(environment)
    failure_log = read_failure_logs(environment)

    # Determine status & banner
    if step_outcome == "failure" or failure_reason:
        status_badge = "🔴 **Failed / Action Required**"
        status_desc = "Release execution encountered an error."
    elif step_outcome == "cancelled":
        status_badge = "🟠 **Cancelled / Action Required**"
        status_desc = "Release execution was cancelled before completion."
    elif step_outcome == "timed_out":
        status_badge = "🟠 **Timed Out / Action Required**"
        status_desc = "Release execution exceeded its time limit."
    elif is_release_published:
        status_badge = "🚀 **Release Published**"
        if len(releases) > 1:
            status_desc = f"{len(releases)} releases published successfully."
        elif tag_name:
            status_desc = f"New release created with tag `{tag_name}`"
        else:
            status_desc = "New release published successfully."
    elif pr_url or prs_created:
        status_badge = "📝 **Release PR Ready**"
        status_desc = "Release PR is open and pending review/merge."
    else:
        status_badge = "💤 **No Changes**"
        status_desc = "No new conventional commits or pending releases."

    # Build PR display
    if pr_url:
        pr_display = f"[{pr_url.split('/')[-1]}]({pr_url})"
        if auto_merge == "true":
            pr_display += f" *(Auto-merge: `{merge_method}`)*"
    elif prs_created:
        pr_display = "Release PR opened"
    else:
        pr_display = "—"

    # Build Tag display
    tag_display = f"`{tag_name}`" if tag_name else "—"

    # Build paths released
    if isinstance(paths_released, list) and paths_released:
        paths_display = ", ".join(f"`{p}`" for p in paths_released)
    else:
        paths_display = "—"

    lines = [
        "## 🚀 Release Please Summary",
        "",
        "> 💡 **Tip**: *Release Please* tracks conventional commits (`feat:`, `fix:`, `chore:`, etc.). Once release PRs are merged, tags and GitHub Releases are published automatically.",
        "",
        "### 📊 Status Overview",
        "",
        "| Metric | Details |",
        "| :--- | :--- |",
        f"| **Status** | {status_badge} — {status_desc} |",
        f"| **Target Branch** | `{target_branch}` |",
        f"| **Pull Request** | {pr_display} |",
        f"| **Release Tag** | {tag_display} |",
        f"| **Packages Released** | {paths_display} |",
        f"| **Release and Tag Publication** | `{publication_status}` |",
        f"| **Auto-Merge Requested** | `{auto_merge}` |",
        "",
    ]
    lines.extend(render_release_details(releases))

    # Diagnostics / error details
    if step_outcome in {"failure", "cancelled", "timed_out"} or failure_reason:
        lines.extend([
            "<details open>",
            "<summary>⚠️ <b>Failure Details</b></summary>",
            "",
            "```text",
            failure_reason or "An unknown error occurred during release execution.",
            "```",
            "</details>",
            "",
        ])
        if failure_log:
            lines.extend([
                "<details open>",
                "<summary>🧾 <b>Failure log</b></summary>",
                "",
                failure_log,
                "",
                "</details>",
                "",
            ])
    else:
        lines.extend([
            "<details>",
            "<summary>🔍 <b>Diagnostics</b></summary>",
            "",
            "- **Upstream release-please**: executed cleanly.",
            f"- **Auto-merge mode**: `{auto_merge}` (`{merge_method}`).",
            f"- **Target**: `{target_branch}`.",
            "</details>",
            "",
        ])

    return "\n".join(lines)


def main() -> int:
    print("🏁 Starting step summary generation...")
    summary_content = format_summary(os.environ)
    summary_path_str = os.environ.get("GITHUB_STEP_SUMMARY", "")

    if summary_path_str:
        summary_path = Path(summary_path_str)
        try:
            with summary_path.open("a", encoding="utf-8") as f:
                f.write(summary_content + "\n")
            print("✅ Successfully published step summary to GITHUB_STEP_SUMMARY.")
        except Exception as error:
            print(f"⚠️  Could not write to GITHUB_STEP_SUMMARY: {error}", file=sys.stderr)
            print(summary_content)
    else:
        # Fallback to stdout if GITHUB_STEP_SUMMARY is not set (e.g. local testing)
        print("ℹ️  GITHUB_STEP_SUMMARY environment variable not set; printing summary to stdout:")
        print(summary_content)

    print("🎉 Step summary generation completed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
