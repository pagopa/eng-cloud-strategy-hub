from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tools.local_actions.runner import (  # noqa: E402
    PRE_COMMIT_IMAGE,
    build_pre_commit_run_command,
    build_steps,
    collect_shell_targets,
    restore_directory_snapshot,
    select_steps,
    snapshot_directory,
)


class LocalActionsRunnerTests(unittest.TestCase):
    def test_collect_shell_targets_keeps_only_bash_shebangs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            root = Path(temporary_dir)
            write_file(
                root / ".github/scripts/bootstrap.sh",
                "#!/usr/bin/env bash\necho ok\n",
            )
            write_file(root / "scripts/plain.txt", "not a shell script\n")
            write_file(root / "tests/scripts/fake", "#!/bin/bash\necho fake\n")
            write_file(
                root / "tools/local_actions/runner.py", "#!/usr/bin/env python3\n"
            )
            write_file(root / "local-actions.sh", "#!/usr/bin/env bash\necho run\n")

            targets = collect_shell_targets(
                root,
                (
                    ".github/scripts",
                    "scripts",
                    "tests/scripts",
                    "tools",
                    "local-actions.sh",
                ),
            )

            self.assertEqual(
                [
                    ".github/scripts/bootstrap.sh",
                    "local-actions.sh",
                    "tests/scripts/fake",
                ],
                [target.relative_to(root).as_posix() for target in targets],
            )

    def test_select_steps_expands_aliases_and_skip_filters(self) -> None:
        selected = select_steps(
            build_steps(),
            only_values=["code-analysis"],
            skip_values=["shell-static-analysis"],
        )

        self.assertEqual(
            ["actionlint", "copilot-entrypoints"],
            [step.step_id for step in selected],
        )

    def test_pre_commit_command_matches_workflow_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            root = Path(temporary_dir)
            cache_dir = root / "tmp/local-actions/pre-commit-cache"

            command = build_pre_commit_run_command(root, cache_dir)

            self.assertEqual("docker", command[0])
            self.assertIn(PRE_COMMIT_IMAGE, command)
            self.assertIn("PRE_COMMIT_HOME=/pre-commit-cache", command)
            self.assertIn(f"{cache_dir}:/pre-commit-cache", command)
            self.assertIn(f"{root}:/lint", command)
            self.assertIn("--all-files", command)
            self.assertIn("--show-diff-on-failure", command)
            self.assertIn(f"USERID={os.getuid()}:{os.getgid()}", command)

    def test_directory_snapshot_restores_original_contents(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            root = Path(temporary_dir)
            source = root / "logs"
            snapshot_path = root / "tmp/snapshot"
            write_file(source / "aws.stdout", "before\n")

            snapshot = snapshot_directory(source, snapshot_path, dry_run=False)
            (source / "aws.stdout").unlink()
            write_file(source / "new.log", "after\n")

            restore_directory_snapshot(snapshot, dry_run=False)

            self.assertEqual("before\n", (source / "aws.stdout").read_text())
            self.assertFalse((source / "new.log").exists())
            self.assertFalse(snapshot_path.exists())


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
