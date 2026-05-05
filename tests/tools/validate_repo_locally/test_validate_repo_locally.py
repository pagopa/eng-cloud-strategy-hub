from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
RUNNER_PATH = ROOT / "tools/validate_repo_locally/validate_repo_locally.py"


def load_module(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load module from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


runner = load_module(RUNNER_PATH, "validate_repo_locally_source")


class ValidateRepoLocallyTests(unittest.TestCase):
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
                root / "tools/validate_repo_locally/validate_repo_locally.py",
                "#!/usr/bin/env python3\n",
            )
            write_file(
                root / "validate-repo-locally.sh",
                "#!/usr/bin/env bash\necho run\n",
            )

            targets = runner.collect_shell_targets(
                root,
                (
                    ".github/scripts",
                    "scripts",
                    "tests/scripts",
                    "tools",
                    "validate-repo-locally.sh",
                ),
            )

            self.assertEqual(
                [
                    ".github/scripts/bootstrap.sh",
                    "tests/scripts/fake",
                    "validate-repo-locally.sh",
                ],
                [target.relative_to(root).as_posix() for target in targets],
            )

    def test_select_steps_expands_aliases_and_skip_filters(self) -> None:
        selected = runner.select_steps(
            runner.build_steps(),
            only_values=["code-analysis"],
            skip_values=["shell-static-analysis"],
        )

        self.assertEqual(
            ["actionlint", "copilot-entrypoints"],
            [step.step_id for step in selected],
        )

    def test_parse_args_rejects_interactive_and_yes_together(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                runner.parse_args(["--interactive", "--yes"])

    def test_prompt_for_steps_returns_original_selection_when_not_interactive(
        self,
    ) -> None:
        steps = runner.build_steps()[:2]

        selected = runner.prompt_for_steps(
            steps,
            interactive=False,
            console=runner.Console(use_color=False),
        )

        self.assertEqual(steps, selected)

    def test_prompt_for_steps_interactive_requires_tty(self) -> None:
        with mock.patch("sys.stdin.isatty", return_value=False):
            with self.assertRaises(SystemExit):
                runner.prompt_for_steps(
                    runner.build_steps()[:1],
                    interactive=True,
                    console=runner.Console(use_color=False),
                )

    def test_prompt_for_steps_interactive_uses_questionary_checkbox(self) -> None:
        steps = runner.build_steps()[:3]
        captured: dict[str, object] = {}
        console = runner.Console(use_color=False)
        console.title = lambda _message: None  # type: ignore[method-assign]

        class FakeChoice:
            def __init__(self, *, title: str, value: str, checked: bool) -> None:
                self.title = title
                self.value = value
                self.checked = checked

        class FakePrompt:
            def ask(self) -> list[str]:
                return [steps[0].step_id, steps[2].step_id]

        class FakeQuestionary:
            Choice = FakeChoice

            @staticmethod
            def checkbox(
                message: str, *, choices: list[FakeChoice], instruction: str
            ) -> FakePrompt:
                captured["message"] = message
                captured["choices"] = choices
                captured["instruction"] = instruction
                return FakePrompt()

        with mock.patch("sys.stdin.isatty", return_value=True):
            with mock.patch.object(
                runner, "import_questionary", return_value=FakeQuestionary()
            ):
                selected = runner.prompt_for_steps(
                    steps,
                    interactive=True,
                    console=console,
                )

        self.assertEqual(
            [steps[0].step_id, steps[2].step_id],
            [step.step_id for step in selected],
        )
        self.assertEqual("Select the local checks to run", captured["message"])
        self.assertEqual("Space toggles, Enter confirms", captured["instruction"])
        self.assertTrue(
            all(choice.checked for choice in captured["choices"])  # type: ignore[arg-type]
        )

    def test_pre_commit_command_matches_workflow_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            root = Path(temporary_dir)
            cache_dir = root / "tmp/validate-repo-locally/pre-commit-cache"

            command = runner.build_pre_commit_run_command(root, cache_dir)

            self.assertEqual("docker", command[0])
            self.assertIn(runner.PRE_COMMIT_IMAGE, command)
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

            snapshot = runner.snapshot_directory(source, snapshot_path, dry_run=False)
            (source / "aws.stdout").unlink()
            write_file(source / "new.log", "after\n")

            runner.restore_directory_snapshot(snapshot, dry_run=False)

            self.assertEqual("before\n", (source / "aws.stdout").read_text())
            self.assertFalse((source / "new.log").exists())
            self.assertFalse(snapshot_path.exists())


def write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
