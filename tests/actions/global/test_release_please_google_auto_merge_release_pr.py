from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

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
                        "CONFIG_FILE_INPUT": str(config_file),
                        "MANIFEST_FILE_INPUT": str(manifest_file),
                        "DEBUG_INPUT": "false",
                    }
                )


if __name__ == "__main__":
    unittest.main()
