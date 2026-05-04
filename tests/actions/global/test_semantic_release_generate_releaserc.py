from __future__ import annotations

import argparse
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = ROOT / "actions/global/semantic-release/scripts/generate-releaserc.py"
VALIDATOR_PATH = ROOT / "actions/global/semantic-release/scripts/validate_inputs.py"


def load_module(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load module from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


generate_releaserc = load_module(SCRIPT_PATH, "semantic_release_generate_releaserc")
validate_inputs = load_module(VALIDATOR_PATH, "semantic_release_validate_inputs")


class GenerateReleaseRcTests(unittest.TestCase):
    def test_build_config_uses_default_wrapper_contract(self) -> None:
        args = argparse.Namespace(
            branches='["main"]',
            tag_format="v${version}",
            preset="angular",
            changelog_file="CHANGELOG.md",
            git_author_name="github-actions[bot]",
            git_author_email="41898282+github-actions[bot]@users.noreply.github.com",
            release_rules='[{"type": "breaking", "release": "major"}]',
        )

        config = generate_releaserc.build_config(args)

        self.assertEqual(["main"], config["branches"])
        self.assertEqual("v${version}", config["tagFormat"])
        self.assertIn("@semantic-release/github", config["plugins"])
        self.assertEqual("CHANGELOG.md", config["plugins"][2][1]["changelogFile"])
        self.assertIn("[skip ci]", config["plugins"][3][1]["message"])

    def test_build_config_rejects_invalid_json(self) -> None:
        args = argparse.Namespace(
            branches="not-json",
            tag_format="v${version}",
            preset="angular",
            changelog_file="CHANGELOG.md",
            git_author_name="github-actions[bot]",
            git_author_email="41898282+github-actions[bot]@users.noreply.github.com",
            release_rules="[]",
        )

        with self.assertRaisesRegex(ValueError, "branches must be valid JSON"):
            generate_releaserc.build_config(args)

    def test_main_supports_environment_execution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            output_path = Path(temporary_dir) / ".releaserc.json"
            original_environment = dict(generate_releaserc.os.environ)
            try:
                generate_releaserc.os.environ.clear()
                generate_releaserc.os.environ.update(
                    {
                        "RELEASERC_OUTPUT_PATH": str(output_path),
                        "SEMANTIC_BRANCHES_INPUT": '["main"]',
                        "TAG_FORMAT_INPUT": "v${version}",
                        "PRESET_INPUT": "angular",
                        "CHANGELOG_FILE_INPUT": "CHANGELOG.md",
                        "GIT_AUTHOR_NAME_INPUT": "github-actions[bot]",
                        "GIT_AUTHOR_EMAIL_INPUT": "41898282+github-actions[bot]@users.noreply.github.com",
                        "RELEASE_RULES_INPUT": '[{"type": "breaking", "release": "major"}]',
                        "DEBUG_INPUT": "false",
                    }
                )

                exit_code = generate_releaserc.main([])
                self.assertEqual(0, exit_code)
                self.assertTrue(output_path.exists())
            finally:
                generate_releaserc.os.environ.clear()
                generate_releaserc.os.environ.update(original_environment)


class SemanticReleaseValidateInputsTests(unittest.TestCase):
    def test_validate_inputs_accepts_default_scalars(self) -> None:
        validate_inputs.validate_inputs(
            {
                "GITHUB_TOKEN_INPUT": "token",
                "CHECKOUT_INPUT": "true",
                "SEMANTIC_VERSION_INPUT": "24.1.1",
                "TAG_FORMAT_INPUT": "v${version}",
                "CHANGELOG_FILE_INPUT": "CHANGELOG.md",
                "DEBUG_INPUT": "false",
            }
        )

    def test_validate_inputs_rejects_invalid_boolean(self) -> None:
        with self.assertRaisesRegex(
            ValueError, "CHECKOUT_INPUT must be 'true' or 'false'"
        ):
            validate_inputs.validate_inputs(
                {
                    "GITHUB_TOKEN_INPUT": "token",
                    "CHECKOUT_INPUT": "maybe",
                    "SEMANTIC_VERSION_INPUT": "24.1.1",
                    "TAG_FORMAT_INPUT": "v${version}",
                    "CHANGELOG_FILE_INPUT": "CHANGELOG.md",
                    "DEBUG_INPUT": "false",
                }
            )


if __name__ == "__main__":
    unittest.main()
