from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
AUTO_MERGE_PATH = (
    ROOT / "actions/global/release-please-google/scripts/auto_merge_release_pr.py"
)
VALIDATOR_PATH = (
    ROOT / "actions/global/release-please-google/scripts/validate_inputs.py"
)


def load_module(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load module from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


auto_merge = load_module(AUTO_MERGE_PATH, "release_please_auto_merge")
validate_inputs = load_module(VALIDATOR_PATH, "release_please_validate_inputs")


class AutoMergeReleasePrTests(unittest.TestCase):
    def test_is_release_please_title_accepts_scoped_and_unscoped_titles(
        self,
    ) -> None:
        accepted_titles = (
            "chore: release main",
            "chore(main): release foo-bar v1.2.3",
            "chore(release-please): release v2.0.0",
        )

        for title in accepted_titles:
            with self.subTest(title=title):
                self.assertTrue(auto_merge.is_release_please_title(title))

    def test_is_release_please_title_rejects_non_release_titles(self) -> None:
        rejected_titles = (
            "feat: release foo-bar v1.2.3",
            "chore(main): update dependencies",
            "docs: chore(main): release notes",
        )

        for title in rejected_titles:
            with self.subTest(title=title):
                self.assertFalse(auto_merge.is_release_please_title(title))

    def test_normalize_release_please_outputs_filters_release_prs(self) -> None:
        release_prs = auto_merge.normalize_release_please_outputs(
            raw_pr=(
                '{"number":42,"headBranchName":"release-please--branches--main",'
                '"baseBranchName":"main",'
                '"title":"chore(main): release foo-bar v1.2.3"}'
            ),
            raw_prs=(
                "["
                '{"number":42,"headBranchName":"release-please--branches--main",'
                '"baseBranchName":"main",'
                '"title":"chore(main): release foo-bar v1.2.3"},'
                '{"number":99,"headBranchName":"feature/not-release",'
                '"baseBranchName":"main","title":"feat: something"}'
                "]"
            ),
            target_branch="main",
            server_url="https://github.com",
            repository="pagopa/eng-cloud-strategy-hub",
        )

        self.assertEqual(1, len(release_prs))
        self.assertEqual(42, release_prs[0].number)
        self.assertEqual(
            "https://github.com/pagopa/eng-cloud-strategy-hub/pull/42",
            release_prs[0].url,
        )

    def test_emit_pr_outputs_writes_caller_contract(self) -> None:
        release_pr = auto_merge.ReleasePullRequest(
            number=42,
            url="https://github.com/pagopa/eng-cloud-strategy-hub/pull/42",
            title="chore: release main",
            head_branch_name="release-please--branches--main",
            base_branch_name="main",
            source="release-please-output",
        )

        with tempfile.TemporaryDirectory() as temporary_dir:
            output_path = Path(temporary_dir) / "github-output.txt"
            auto_merge.emit_pr_outputs(output_path, [release_pr], "false")
            content = output_path.read_text(encoding="utf-8")

        self.assertIn(
            "pr=https://github.com/pagopa/eng-cloud-strategy-hub/pull/42", content
        )
        self.assertIn("auto_merge_enabled=false", content)
        self.assertIn('"source":"release-please-output"', content)

    def test_resolve_release_prs_skips_missing_gh_when_auto_merge_is_disabled(
        self,
    ) -> None:
        original_gh_available = auto_merge.gh_available
        try:
            auto_merge.gh_available = lambda: False
            release_prs = auto_merge.resolve_release_prs(
                {
                    "RP_TARGET_BRANCH": "main",
                    "RP_AUTO_MERGE": "false",
                    "RP_DEBUG": "false",
                    "RP_PR": "",
                    "RP_PRS": "",
                },
                allow_fallback=True,
            )
        finally:
            auto_merge.gh_available = original_gh_available

        self.assertEqual([], release_prs)

    def test_validate_merge_method_rejects_unknown_value(self) -> None:
        with self.assertRaisesRegex(ValueError, "RP_MERGE_METHOD must be one of"):
            auto_merge.validate_merge_method({"RP_MERGE_METHOD": "invalid"})

    def test_resolve_release_prs_filters_unverified_upstream_candidate(self) -> None:
        with (
            patch.object(auto_merge, "gh_available", return_value=True),
            patch.object(
                auto_merge,
                "run_gh_json",
                return_value={
                    "number": 42,
                    "url": "https://github.com/pagopa/eng-cloud-strategy-hub/pull/42",
                    "title": "chore(main): release foo-bar v1.2.3",
                    "headRefName": "release-please--branches--main",
                    "baseRefName": "main",
                    "author": {"login": "octocat"},
                    "isCrossRepository": False,
                    "state": "OPEN",
                },
            ),
        ):
            release_prs = auto_merge.resolve_release_prs(
                {
                    "RP_TARGET_BRANCH": "main",
                    "RP_AUTO_MERGE": "true",
                    "RP_DEBUG": "false",
                    "RP_PR": (
                        '{"number":42,"headBranchName":"release-please--branches--main",'
                        '"baseBranchName":"main",'
                        '"title":"chore(main): release foo-bar v1.2.3"}'
                    ),
                    "RP_PRS": "",
                },
                allow_fallback=False,
            )

        self.assertEqual([], release_prs)

    def test_enable_auto_merge_skips_merge_conflicts_and_continues(self) -> None:
        release_prs = [
            auto_merge.ReleasePullRequest(
                number=28,
                url="https://github.com/pagopa/eng-cloud-strategy-hub/pull/28",
                title="chore(main): release code 1.0.0",
                head_branch_name="release-please--branches--main--components--code",
                base_branch_name="main",
                source="release-please-output",
            ),
            auto_merge.ReleasePullRequest(
                number=29,
                url="https://github.com/pagopa/eng-cloud-strategy-hub/pull/29",
                title="chore(main): release scripts 1.1.0",
                head_branch_name="release-please--branches--main--components--scripts",
                base_branch_name="main",
                source="release-please-output",
            ),
        ]

        conflict = auto_merge.subprocess.CompletedProcess(
            args=["gh", "pr", "merge"],
            returncode=1,
            stdout="",
            stderr="GraphQL: Pull Request has merge conflicts (mergePullRequest)",
        )
        success = auto_merge.subprocess.CompletedProcess(
            args=["gh", "pr", "merge"],
            returncode=0,
            stdout="",
            stderr="",
        )

        with (
            patch.object(auto_merge, "gh_available", return_value=True),
            patch.object(
                auto_merge.subprocess, "run", side_effect=[conflict, success]
            ) as run,
        ):
            auto_merge.enable_auto_merge(release_prs, "squash")

        first_call_args = run.call_args_list[0].args[0]
        second_call_args = run.call_args_list[1].args[0]
        self.assertIn("--delete-branch", first_call_args)
        self.assertIn("--delete-branch", second_call_args)

    def test_enable_auto_merge_skips_unavailable_auto_merge_and_continues(
        self,
    ) -> None:
        release_prs = [
            auto_merge.ReleasePullRequest(
                number=36,
                url="https://github.com/pagopa/eng-cloud-strategy-hub/pull/36",
                title="chore(main): release scripts 1.2.0",
                head_branch_name=(
                    "release-please--branches--main--components--scripts"
                ),
                base_branch_name="main",
                source="release-please-output",
            ),
            auto_merge.ReleasePullRequest(
                number=37,
                url="https://github.com/pagopa/eng-cloud-strategy-hub/pull/37",
                title="chore(main): release actions 1.1.0",
                head_branch_name=(
                    "release-please--branches--main--components--actions"
                ),
                base_branch_name="main",
                source="release-please-output",
            ),
        ]

        auto_merge_unavailable = auto_merge.subprocess.CompletedProcess(
            args=["gh", "pr", "merge"],
            returncode=1,
            stdout="",
            stderr=(
                "GraphQL: Pull request Branch does not have required protected "
                "branch rules (enablePullRequestAutoMerge)"
            ),
        )
        success = auto_merge.subprocess.CompletedProcess(
            args=["gh", "pr", "merge"],
            returncode=0,
            stdout="",
            stderr="",
        )

        with (
            patch.object(auto_merge, "gh_available", return_value=True),
            patch.object(
                auto_merge.subprocess,
                "run",
                side_effect=[auto_merge_unavailable, success],
            ),
        ):
            auto_merge.enable_auto_merge(release_prs, "squash")

    def test_enable_auto_merge_raises_for_permission_errors(self) -> None:
        release_prs = [
            auto_merge.ReleasePullRequest(
                number=28,
                url="https://github.com/pagopa/eng-cloud-strategy-hub/pull/28",
                title="chore(main): release code 1.0.0",
                head_branch_name="release-please--branches--main--components--code",
                base_branch_name="main",
                source="release-please-output",
            )
        ]

        permission_error = auto_merge.subprocess.CompletedProcess(
            args=["gh", "pr", "merge"],
            returncode=1,
            stdout="",
            stderr="GraphQL: Resource not accessible by integration (mergePullRequest)",
        )

        with (
            patch.object(auto_merge, "gh_available", return_value=True),
            patch.object(auto_merge.subprocess, "run", return_value=permission_error),
        ):
            with self.assertRaisesRegex(
                RuntimeError, "does not have enough permissions"
            ):
                auto_merge.enable_auto_merge(release_prs, "squash")


class ReleasePleaseValidateInputsTests(unittest.TestCase):
    def test_validate_wrapper_inputs_accepts_defaults(self) -> None:
        validate_inputs.validate_wrapper_inputs(
            {
                "GITHUB_TOKEN_INPUT": "token",
                "CHECKOUT_INPUT": "true",
                "TARGET_BRANCH_INPUT": "main",
                "AUTO_MERGE_INPUT": "true",
                "MERGE_METHOD_INPUT": "squash",
                "DEBUG_INPUT": "false",
            }
        )

    def test_validate_consumer_files_rejects_invalid_json(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            root = Path(temporary_dir)
            config_file = root / "release-please-config.json"
            manifest_file = root / ".release-please-manifest.json"
            config_file.write_text("not-json", encoding="utf-8")
            manifest_file.write_text("{}", encoding="utf-8")

            with self.assertRaisesRegex(
                ValueError, "release-please config file must be valid JSON"
            ):
                validate_inputs.validate_consumer_files(
                    {
                        "GITHUB_WORKSPACE": str(root),
                        "CONFIG_FILE_INPUT": "release-please-config.json",
                        "MANIFEST_FILE_INPUT": ".release-please-manifest.json",
                        "DEBUG_INPUT": "false",
                    }
                )

    def test_validate_consumer_files_rejects_paths_outside_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            root = Path(temporary_dir)
            outside_root = root.parent / "outside.json"
            outside_root.write_text("{}", encoding="utf-8")

            with self.assertRaisesRegex(
                ValueError, "must use a repository-relative path"
            ):
                validate_inputs.validate_consumer_files(
                    {
                        "GITHUB_WORKSPACE": str(root),
                        "CONFIG_FILE_INPUT": str(outside_root),
                        "MANIFEST_FILE_INPUT": ".release-please-manifest.json",
                        "DEBUG_INPUT": "false",
                    }
                )


if __name__ == "__main__":
    unittest.main()
