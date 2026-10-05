from __future__ import annotations

import os
import re
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SCRIPT_DIR = ROOT / "scripts/aws/terraform-sh"
WRAPPER = SCRIPT_DIR / "terraform.sh"
README = SCRIPT_DIR / "README.md"
FAKES_DIR = ROOT / "tests/scripts/cross-provider/terraform-sh/fakes"
OPTION_PATTERN = re.compile(r"(?<![\w-])--[a-z][a-z-]*")
ISOLATED_PREFIXES = ("AWS_", "TF_", "FAKE_", "TERRAFORM_", "CI")


def isolated_env(tmpdir: Path, logs: Path) -> dict[str, str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith(ISOLATED_PREFIXES)
    }
    env.update(
        {
            "PATH": f"{FAKES_DIR}:{os.environ.get('PATH', '/usr/bin:/bin')}",
            "TMPDIR": str(tmpdir),
            "FAKE_LOG_DIR": str(logs),
            "CI": "false",
        }
    )
    return env


def usage_text() -> str:
    with tempfile.TemporaryDirectory() as temporary_dir:
        base = Path(temporary_dir)
        result = subprocess.run(
            ["bash", str(WRAPPER), "help"],
            env=isolated_env(base, base),
            capture_output=True,
            text=True,
            timeout=30,
            check=True,
        )
    return result.stdout


def parse_cli_source() -> str:
    source = WRAPPER.read_text(encoding="utf-8")
    start = source.index("parse_cli() {")
    return source[start : source.index("\n}\n", start)]


def readme_usage_commands() -> list[list[str]]:
    text = README.read_text(encoding="utf-8")
    section = text[text.index("## Usage") :]
    block = section[section.index("```bash") + len("```bash") : section.index("```", section.index("```bash") + 1)]
    joined = block.replace("\\\n", " ")
    return [
        shlex.split(line)
        for line in joined.splitlines()
        if line.strip().startswith("bash ./terraform.sh")
    ]


class VersionMetadataTests(unittest.TestCase):
    def test_version_header_variable_and_changelog_agree(self) -> None:
        source = WRAPPER.read_text(encoding="utf-8")
        header = re.search(r"^# Version: (\S+)$", source, re.MULTILINE)
        variable = re.search(r'^vers="([^"]+)"$', source, re.MULTILINE)
        changelog = re.search(r"^# Change log:\n# - (\S+) ", source, re.MULTILINE)

        self.assertIsNotNone(header)
        self.assertIsNotNone(variable)
        self.assertIsNotNone(changelog)
        self.assertEqual(header.group(1), variable.group(1))  # type: ignore[union-attr]
        self.assertEqual(header.group(1), changelog.group(1))  # type: ignore[union-attr]


class OptionContractTests(unittest.TestCase):
    def test_usage_documents_exactly_the_parsed_options(self) -> None:
        parsed = set(OPTION_PATTERN.findall(parse_cli_source()))
        documented = set(OPTION_PATTERN.findall(usage_text()))

        self.assertEqual(parsed, documented)

    def test_readme_documents_every_usage_option(self) -> None:
        documented = set(OPTION_PATTERN.findall(usage_text()))
        in_readme = set(OPTION_PATTERN.findall(README.read_text(encoding="utf-8")))

        self.assertEqual(set(), documented - in_readme)


class ReadmeExampleTests(unittest.TestCase):
    def test_usage_examples_run_without_calling_terraform(self) -> None:
        commands = readme_usage_commands()
        self.assertGreater(len(commands), 1)

        for command in commands:
            with self.subTest(command=shlex.join(command)):
                self.assertTrue(command[2] == "help" or "--dry-run" in command)
                with tempfile.TemporaryDirectory() as temporary_dir:
                    base = Path(temporary_dir)
                    result = subprocess.run(
                        command,
                        cwd=SCRIPT_DIR,
                        env=isolated_env(base, base),
                        stdin=subprocess.DEVNULL,
                        capture_output=True,
                        text=True,
                        timeout=60,
                        check=False,
                    )
                    self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                    self.assertFalse((base / "terraform.log").exists())


if __name__ == "__main__":
    unittest.main()
