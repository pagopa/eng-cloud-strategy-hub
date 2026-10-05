from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
WRAPPER = ROOT / "scripts/aws/terraform-sh/terraform.sh"
TERRAFORM = shutil.which("terraform")
ISOLATED_PREFIXES = ("AWS_", "TF_", "FAKE_", "TERRAFORM_", "CI")
MAIN_TF = """
terraform {
  backend "local" {}
}

variable "winner" {
  type    = string
  default = "variable_default"
}

output "winner" {
  value = var.winner
}
"""


@unittest.skipUnless(TERRAFORM, "terraform binary not available")
class RealTerraformTestCase(unittest.TestCase):
    def setUp(self) -> None:
        workspace = tempfile.TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        base = Path(workspace.name).resolve()
        self.root = base / "root"
        self.tmpdir = base / "tmpdir"
        self.tmpdir.mkdir()
        self.write("main.tf", MAIN_TF)
        self.write("env/dev/backend.ini", "path=dev.tfstate\n")

    def write(self, relative: str, content: str) -> None:
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def remove(self, relative: str) -> None:
        (self.root / relative).unlink(missing_ok=True)

    def run_wrapper(
        self, *args: str, extra_env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(ISOLATED_PREFIXES)
        }
        env.update(
            {
                "TMPDIR": str(self.tmpdir),
                "TERRAFORM_ROOT": str(self.root),
                "CI": "true",
                "TF_IN_AUTOMATION": "1",
            }
        )
        env.update(extra_env or {})
        return subprocess.run(
            ["bash", str(WRAPPER), *args],
            cwd=self.root,
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=180,
            check=False,
        )

    def assert_status(
        self, expected: int, result: subprocess.CompletedProcess[str]
    ) -> None:
        self.assertEqual(expected, result.returncode, result.stdout + result.stderr)

    def applied_winner(self, *apply_args: str, extra_env: dict[str, str] | None = None) -> str:
        self.assert_status(
            0,
            self.run_wrapper("apply", "dev", *apply_args, "-auto-approve", extra_env=extra_env),
        )
        result = self.run_wrapper("output", "dev", "-raw", "winner")
        self.assert_status(0, result)
        return result.stdout


class RealTerraformPrecedenceTests(RealTerraformTestCase):
    def test_wrapper_order_matches_declared_precedence(self) -> None:
        self.write("env/dev/a.tfvars", 'winner = "env_a"\n')
        self.write("env/dev/z.tfvars", 'winner = "env_z"\n')
        self.write("env/dev/terraform.tfvars", 'winner = "env_default"\n')
        self.write("overrides/o.tfvars", 'winner = "override"\n')

        with self.subTest(layer="cli -var"):
            self.assertEqual(
                "cli",
                self.applied_winner("--tfvars", "overrides/o.tfvars", "-var=winner=cli"),
            )
        with self.subTest(layer="--tfvars override"):
            self.assertEqual("override", self.applied_winner("--tfvars", "overrides/o.tfvars"))
        with self.subTest(layer="env terraform.tfvars"):
            self.assertEqual("env_default", self.applied_winner())

        self.remove("env/dev/terraform.tfvars")
        with self.subTest(layer="last env tfvars"):
            self.assertEqual("env_z", self.applied_winner())

        self.remove("env/dev/z.tfvars")
        with self.subTest(layer="env tfvars over TF_VAR"):
            self.assertEqual(
                "env_a", self.applied_winner(extra_env={"TF_VAR_winner": "from_env"})
            )

        self.remove("env/dev/a.tfvars")
        with self.subTest(layer="TF_VAR"):
            self.assertEqual(
                "from_env", self.applied_winner(extra_env={"TF_VAR_winner": "from_env"})
            )


class RealTerraformPlanTests(RealTerraformTestCase):
    def test_detailed_exitcode_from_environment_reports_changes(self) -> None:
        self.assert_status(0, self.run_wrapper("init", "dev"))
        for variable in ("TF_CLI_ARGS", "TF_CLI_ARGS_plan"):
            with self.subTest(variable=variable):
                changed = self.run_wrapper(
                    "plan", "dev", "--skip-init",
                    extra_env={variable: "-detailed-exitcode"},
                )
                self.assert_status(2, changed)
                self.assertIn("CHANGES PRESENT", changed.stderr)
                self.assertNotIn("FAILED", changed.stderr)

    def test_detailed_exitcode_reports_changes_then_clean(self) -> None:
        changed = self.run_wrapper("plan", "dev", "-detailed-exitcode")
        self.assert_status(2, changed)
        self.assertIn("CHANGES PRESENT", changed.stderr)

        self.applied_winner()

        clean = self.run_wrapper("plan", "dev", "-detailed-exitcode")
        self.assert_status(0, clean)

    def test_saved_plan_applies_without_var_files(self) -> None:
        self.write("env/dev/terraform.tfvars", 'winner = "from_plan"\n')
        self.assert_status(0, self.run_wrapper("plan", "dev", "-out=review.tfplan"))

        self.assert_status(0, self.run_wrapper("apply", "dev", "review.tfplan"))

        result = self.run_wrapper("output", "dev", "-raw", "winner")
        self.assert_status(0, result)
        self.assertEqual("from_plan", result.stdout)


if __name__ == "__main__":
    unittest.main()
