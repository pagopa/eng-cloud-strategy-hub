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
        status_desc = f"New release created with tag `{tag_name}`" if tag_name else "New release published successfully."
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
