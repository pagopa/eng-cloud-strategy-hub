from __future__ import annotations

import hashlib
import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
WRAPPER = ROOT / "scripts/aws/terraform-sh/terraform.sh"
SUITE_DIR = ROOT / "tests/scripts/cross-provider/terraform-sh"
FAKES_DIR = SUITE_DIR / "fakes"
FIXTURE_ROOT = SUITE_DIR / "fixtures/aws-root"
TARGET_FILE = SUITE_DIR / "fixtures/target-test.tf"
SECRET_VALUES = {
    "access_key": "SENTINEL_ACCESS a b$c",
    "secret_key": "SENTINEL_SECRET;x",
    "token": "SENTINEL_TOKEN'q",
}
ISOLATED_PREFIXES = ("AWS_", "TF_", "FAKE_", "TERRAFORM_", "CI")


class WrapperTestCase(unittest.TestCase):
    def setUp(self) -> None:
        workspace = tempfile.TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        base = Path(workspace.name).resolve()
        self.root = base / "root"
        self.logs = base / "logs"
        self.tmpdir = base / "tmpdir"
        shutil.copytree(FIXTURE_ROOT, self.root)
        self.logs.mkdir()
        self.tmpdir.mkdir()

    def write(self, relative: str, content: str = "") -> Path:
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        return target

    def run_wrapper(
        self,
        *args: str,
        extra_env: dict[str, str] | None = None,
        use_default_root: bool = False,
        wrapper_path: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(ISOLATED_PREFIXES)
        }
        env.update(
            {
                "PATH": f"{FAKES_DIR}:{os.environ.get('PATH', '/usr/bin:/bin')}",
                "TMPDIR": str(self.tmpdir),
                "FAKE_LOG_DIR": str(self.logs),
                "CI": "false",
            }
        )
        if not use_default_root:
            env["TERRAFORM_ROOT"] = str(self.root)
        env.update(extra_env or {})
        return subprocess.run(
            ["bash", str(wrapper_path or WRAPPER), *args],
            cwd=self.root,
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

    def terraform_working_directories(self) -> list[str]:
        log_file = self.logs / "terraform.log"
        if not log_file.exists():
            return []
        return [
            line.split(" argv=", 1)[0].removeprefix("cwd=")
            for line in log_file.read_text(encoding="utf-8").splitlines()
        ]

    def terraform_calls(self) -> list[list[str]]:
        log_file = self.logs / "terraform.log"
        if not log_file.exists():
            return []
        calls = []
        for line in log_file.read_text(encoding="utf-8").splitlines():
            argv_part = line.split(" argv=", 1)[1].rsplit(" env=", 1)[0]
            calls.append(shlex.split(argv_part))
        return calls

    def calls_for(self, subcommand: str) -> list[list[str]]:
        return [call for call in self.terraform_calls() if call[:1] == [subcommand]]

    def var_args(self, argv: list[str]) -> list[str]:
        prefix = f"{self.root}/"
        return [
            arg.replace(prefix, "")
            for arg in argv
            if arg.startswith(("-var-file=", "-var="))
        ]

    def tree_digest(self, base: Path) -> dict[str, str]:
        digest = {}
        for path in sorted(base.rglob("*")):
            key = path.relative_to(base).as_posix()
            if path.is_file():
                digest[key] = hashlib.sha256(path.read_bytes()).hexdigest()
            else:
                digest[key] = "dir"
        return digest

    def assert_success(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def assert_failure(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)


class TfvarsPrecedenceTests(WrapperTestCase):
    def test_env_files_then_default_then_overrides_then_passthrough(self) -> None:
        self.write("env/dev/b.tfvars")
        self.write("env/dev/a.tfvars")
        self.write("env/dev/z.tfvars.json", "{}")
        self.write("overrides/second.tfvars")

        result = self.run_wrapper(
            "plan",
            "dev",
            "--tfvars",
            "overrides/custom.tfvars",
            "--tfvars",
            "overrides/second.tfvars",
            "-var-file=cli.tfvars",
            "-var=winner=cli",
        )

        self.assert_success(result)
        self.assertEqual(
            [
                "-var-file=env/dev/a.tfvars",
                "-var-file=env/dev/b.tfvars",
                "-var-file=env/dev/z.tfvars.json",
                "-var-file=env/dev/terraform.tfvars",
                "-var-file=overrides/custom.tfvars",
                "-var-file=overrides/second.tfvars",
                "-var-file=cli.tfvars",
                "-var=winner=cli",
            ],
            self.var_args(self.calls_for("plan")[-1]),
        )

    def test_both_defaults_follow_terraform_native_order(self) -> None:
        self.write("env/dev/terraform.tfvars.json", "{}")
        self.write("env/dev/a.tfvars")

        result = self.run_wrapper("plan", "dev", "--tfvars", "overrides/custom.tfvars")

        self.assert_success(result)
        self.assertEqual(
            [
                "-var-file=env/dev/a.tfvars",
                "-var-file=env/dev/terraform.tfvars",
                "-var-file=env/dev/terraform.tfvars.json",
                "-var-file=overrides/custom.tfvars",
            ],
            self.var_args(self.calls_for("plan")[-1]),
        )

    def test_json_only_default_precedes_overrides(self) -> None:
        self.write("env/jsononly/a.tfvars")

        result = self.run_wrapper(
            "plan", "jsononly", "--tfvars", "overrides/custom.tfvars"
        )

        self.assert_success(result)
        self.assertEqual(
            [
                "-var-file=env/jsononly/a.tfvars",
                "-var-file=env/jsononly/terraform.tfvars.json",
                "-var-file=overrides/custom.tfvars",
            ],
            self.var_args(self.calls_for("plan")[-1]),
        )

    def test_no_default_tfvars_keeps_only_overrides(self) -> None:
        self.write("env/dev/a.tfvars")

        result = self.run_wrapper(
            "plan",
            "dev",
            "--no-default-tfvars",
            "--tfvars",
            "overrides/custom.tfvars",
        )

        self.assert_success(result)
        self.assertEqual(
            ["-var-file=overrides/custom.tfvars"],
            self.var_args(self.calls_for("plan")[-1]),
        )


class DefaultTerraformRootTests(WrapperTestCase):
    def test_symlinked_wrapper_uses_directory_containing_symlink_as_default_root(
        self,
    ) -> None:
        project_wrapper = self.root / "terraform.sh"
        project_wrapper.symlink_to(WRAPPER)

        result = self.run_wrapper(
            "plan",
            "--skip-init",
            use_default_root=True,
            wrapper_path=project_wrapper,
        )

        self.assert_success(result)
        self.assertEqual([str(self.root)], self.terraform_working_directories())


class DryRunTests(WrapperTestCase):
    def assert_dry_run_is_inert(
        self, *args: str, extra_env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        before = self.tree_digest(self.root)

        result = self.run_wrapper(*args, "--dry-run", extra_env=extra_env)

        self.assert_success(result)
        self.assertEqual([], self.terraform_calls())
        self.assertEqual(before, self.tree_digest(self.root))
        self.assertEqual({}, self.tree_digest(self.tmpdir))
        return result

    def test_unlock_without_lock_id_does_not_probe(self) -> None:
        result = self.assert_dry_run_is_inert(
            "unlock", "dev", extra_env={"FAKE_TERRAFORM_LOCK_ERROR": "1"}
        )

        self.assertIn("terraform plan", result.stdout)
        self.assertIn("-lock-timeout=0s", result.stdout)
        self.assertIn("terraform force-unlock -force", result.stdout)

    def test_clean_keeps_local_artifacts(self) -> None:
        self.write(".terraform/providers/marker")
        self.write("tfplan")
        self.write("tfplan.backup")

        result = self.assert_dry_run_is_inert("clean")

        self.assertIn("rm", result.stdout)
        self.assertIn(".terraform", result.stdout)

    def test_debug_bundle_creates_nothing(self) -> None:
        result = self.assert_dry_run_is_inert("debug-bundle", "dev")

        self.assertIn("terraform version", result.stdout)

    def test_summary_creates_no_temporary_plan(self) -> None:
        self.assert_dry_run_is_inert("summ", "dev")


class SecretRedactionTests(WrapperTestCase):
    def setUp(self) -> None:
        super().setUp()
        backend = self.root / "env/dev/backend.ini"
        lines = [f"{key}={value}" for key, value in SECRET_VALUES.items()]
        with backend.open("a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")

    def assert_no_secret_in_output(
        self, result: subprocess.CompletedProcess[str]
    ) -> None:
        output = result.stdout + result.stderr
        for value in SECRET_VALUES.values():
            self.assertNotIn(value, output)
            self.assertNotIn(shlex.quote(value), output)
        for marker in ("SENTINEL_ACCESS", "SENTINEL_SECRET", "SENTINEL_TOKEN"):
            self.assertNotIn(marker, output)

    def test_dry_run_redacts_backend_secrets(self) -> None:
        result = self.run_wrapper("plan", "dev", "--dry-run")

        self.assert_success(result)
        self.assert_no_secret_in_output(result)
        for key in SECRET_VALUES:
            self.assertIn(f"-backend-config={key}=REDACTED", result.stdout)
        self.assertIn("-backend-config=bucket=aws-dev-state", result.stdout)

    def test_failed_init_redacts_and_still_passes_real_values(self) -> None:
        result = self.run_wrapper(
            "plan", "dev", extra_env={"FAKE_TERRAFORM_FAIL_ON": "init"}
        )

        self.assert_failure(result)
        self.assert_no_secret_in_output(result)
        init_argv = self.calls_for("init")[-1]
        for key, value in SECRET_VALUES.items():
            self.assertIn(f"-backend-config={key}={value}", init_argv)


class SavedPlanTests(WrapperTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.write("plans/review.tfplan")
        self.write("plans/other.tfplan")

    def test_positional_plan_without_context(self) -> None:
        result = self.run_wrapper("apply", "plans/review.tfplan")

        self.assert_success(result)
        argv = self.calls_for("apply")[-1]
        self.assertEqual("plans/review.tfplan", argv[-1])
        self.assertEqual([], self.var_args(argv))

    def test_positional_plan_is_resolved_in_selected_root(self) -> None:
        self.write("alternate/review.tfplan")
        result = self.run_wrapper("apply", "review.tfplan", "--root", "alternate")

        self.assert_success(result)
        self.assertEqual("review.tfplan", self.calls_for("apply")[-1][-1])

    def assert_rejected_before_init(self, *args: str, message: str) -> None:
        result = self.run_wrapper(*args)

        self.assert_failure(result)
        self.assertIn(message, result.stderr)
        self.assertEqual([], self.terraform_calls())

    def test_tfplan_with_target_file_is_rejected(self) -> None:
        self.assert_rejected_before_init(
            "apply",
            "dev",
            str(TARGET_FILE),
            "--tfplan",
            "plans/review.tfplan",
            message="saved plan",
        )

    def test_tfplan_with_tfvars_is_rejected(self) -> None:
        self.assert_rejected_before_init(
            "apply",
            "dev",
            "--tfplan",
            "plans/review.tfplan",
            "--tfvars",
            "overrides/custom.tfvars",
            message="saved plan",
        )

    def test_positional_plan_with_tfvars_is_rejected(self) -> None:
        self.assert_rejected_before_init(
            "apply",
            "dev",
            "plans/review.tfplan",
            "--tfvars",
            "overrides/custom.tfvars",
            message="saved plan",
        )

    def test_two_saved_plans_are_rejected(self) -> None:
        self.assert_rejected_before_init(
            "apply",
            "dev",
            "plans/review.tfplan",
            "--tfplan",
            "plans/other.tfplan",
            message="saved plan",
        )

    def test_missing_saved_plan_is_rejected(self) -> None:
        self.assert_rejected_before_init(
            "apply",
            "dev",
            "--tfplan",
            "plans/missing.tfplan",
            message="does not exist",
        )

    def test_positional_plan_omits_var_files(self) -> None:
        result = self.run_wrapper("apply", "dev", "plans/review.tfplan")

        self.assert_success(result)
        apply_argv = self.calls_for("apply")[-1]
        self.assertEqual([], self.var_args(apply_argv))
        self.assertEqual("plans/review.tfplan", apply_argv[-1])

    def test_skip_init_with_saved_plan_runs_only_apply(self) -> None:
        result = self.run_wrapper(
            "apply", "dev", "--tfplan", "plans/review.tfplan", "--skip-init"
        )

        self.assert_success(result)
        self.assertEqual(["apply"], [call[0] for call in self.terraform_calls()])


class InitTests(WrapperTestCase):
    def test_init_forwards_passthrough_arguments(self) -> None:
        result = self.run_wrapper("init", "noenv", "-upgrade", "-backend=false")

        self.assert_success(result)
        init_argv = self.calls_for("init")[-1]
        self.assertIn("-upgrade", init_argv)
        self.assertIn("-backend=false", init_argv)


class UnlockTests(WrapperTestCase):
    def test_ci_probe_error_is_visible_and_temporaries_are_removed(self) -> None:
        result = self.run_wrapper(
            "unlock",
            "dev",
            "--force",
            extra_env={"CI": "true", "FAKE_TERRAFORM_FAIL_ON": "plan"},
        )

        self.assert_failure(result)
        self.assertIn("fake terraform: forced plan failure", result.stderr)
        self.assertEqual("", result.stdout)
        self.assertEqual([], self.calls_for("force-unlock"))
        self.assertEqual({}, self.tree_digest(self.tmpdir))

    def test_explicit_lock_id_initializes_selected_backend_first(self) -> None:
        result = self.run_wrapper("unlock", "dev", "--lock-id", "lock-1", "--force")

        self.assert_success(result)
        calls = self.terraform_calls()
        self.assertEqual(["init", "force-unlock"], [call[0] for call in calls])
        self.assertIn("-backend-config=bucket=aws-dev-state", calls[0])
        self.assertEqual(["force-unlock", "-force", "lock-1"], calls[1])

    def test_unconfirmed_unlock_does_not_force_unlock(self) -> None:
        result = self.run_wrapper("unlock", "dev", "--lock-id", "lock-1")

        self.assert_failure(result)
        self.assertEqual([], self.calls_for("force-unlock"))

    def test_probe_uses_env_var_files_and_leaves_no_temporaries(self) -> None:
        result = self.run_wrapper(
            "unlock", "dev", "--force", extra_env={"FAKE_TERRAFORM_LOCK_ERROR": "1"}
        )

        self.assert_success(result)
        self.assertIn(
            "-var-file=env/dev/terraform.tfvars",
            self.var_args(self.calls_for("plan")[-1]),
        )
        self.assertEqual(
            ["force-unlock", "-force", "fake-lock-id"],
            self.calls_for("force-unlock")[-1],
        )
        self.assertEqual({}, self.tree_digest(self.tmpdir))

    def test_probe_without_lock_leaves_no_temporaries(self) -> None:
        result = self.run_wrapper("unlock", "dev", "--force")

        self.assert_failure(result)
        self.assertIn("Unable to determine a Terraform lock id", result.stderr)
        self.assertEqual([], self.calls_for("force-unlock"))
        self.assertEqual({}, self.tree_digest(self.tmpdir))


class AutoTfvarsTests(WrapperTestCase):
    def test_root_auto_tfvars_are_left_to_terraform(self) -> None:
        self.write("a.auto.tfvars")
        self.write("b.tfvars")

        result = self.run_wrapper("plan")

        self.assert_success(result)
        self.assertEqual(
            ["-var-file=b.tfvars"], self.var_args(self.calls_for("plan")[-1])
        )

    def test_env_auto_tfvars_are_passed_explicitly(self) -> None:
        self.write("env/dev/a.auto.tfvars")

        result = self.run_wrapper("plan", "dev")

        self.assert_success(result)
        self.assertEqual(
            ["-var-file=env/dev/a.auto.tfvars", "-var-file=env/dev/terraform.tfvars"],
            self.var_args(self.calls_for("plan")[-1]),
        )


class BackendIniTests(WrapperTestCase):
    def test_inline_comments_are_not_part_of_values(self) -> None:
        self.write(
            "env/dev/backend.ini",
            "bucket = aws-dev-state # primary bucket\n"
            "aws_region = eu-south-1 ; main region\n"
            "key=path#with-hash\n",
        )

        result = self.run_wrapper("plan", "dev")

        self.assert_success(result)
        init_argv = self.calls_for("init")[-1]
        self.assertIn("-backend-config=bucket=aws-dev-state", init_argv)
        self.assertIn("-backend-config=region=eu-south-1", init_argv)
        self.assertIn("-backend-config=key=path#with-hash", init_argv)


class PassthroughGrammarTests(WrapperTestCase):
    def test_fmt_file_is_forwarded_as_operand(self) -> None:
        self.write("main.tf", "terraform {}\n")
        result = self.run_wrapper("fmt", "main.tf")

        self.assert_success(result)
        self.assertEqual(["fmt", "main.tf"], self.calls_for("fmt")[-1])

    def test_subcommand_without_context_is_forwarded(self) -> None:
        result = self.run_wrapper("state", "list")

        self.assert_success(result)
        self.assertEqual(["state", "list"], self.calls_for("state")[-1])

    def test_subcommand_with_context_uses_context_backend(self) -> None:
        result = self.run_wrapper("state", "dev", "list")

        self.assert_success(result)
        self.assertIn(
            "-backend-config=bucket=aws-dev-state", self.calls_for("init")[-1]
        )
        self.assertEqual(["state", "list"], self.calls_for("state")[-1])

    def test_unknown_context_still_fails_for_plan(self) -> None:
        result = self.run_wrapper("plan", "dvv")

        self.assert_failure(result)
        self.assertIn("No Terraform context 'dvv'", result.stderr)
        self.assertEqual([], self.terraform_calls())


class TargetShortcutTests(WrapperTestCase):
    def test_ambiguous_hcl_is_rejected_before_init(self) -> None:
        for content in (
            '/*\nresource "terraform_data" "commented" {}\n*/\n',
            'locals {\n text = <<EOF\nresource "terraform_data" "text" {}\nEOF\n}\n',
            'locals {\n text = <<-EOF\nresource "terraform_data" "text" {}\nEOF\n}\n',
        ):
            with self.subTest(content=content):
                target = self.write("ambiguous.tf", content)
                result = self.run_wrapper("apply", "dev", str(target), "--dry-run")

                self.assert_failure(result)
                self.assertIn("-target", result.stderr)
                self.assertEqual([], self.terraform_calls())
                self.assertEqual("", result.stdout)

    def test_plain_target_without_final_newline(self) -> None:
        target = self.write("target.tf", 'resource "terraform_data" "active" {}')
        result = self.run_wrapper("plan", "dev", str(target), "--dry-run")

        self.assert_success(result)
        self.assertIn("-target=terraform_data.active", result.stdout)


class OutputStreamTests(WrapperTestCase):
    def test_output_json_stdout_is_machine_readable(self) -> None:
        result = self.run_wrapper("output", "noenv", "-json")

        self.assert_success(result)
        self.assertEqual("fake", json.loads(result.stdout)["example"]["value"])
        self.assertIn("PREFLIGHT", result.stderr)

    def test_summary_json_stdout_is_machine_readable(self) -> None:
        result = self.run_wrapper("summ", "dev", "--summary-format", "json")

        self.assert_success(result)
        self.assertEqual({"create": 1}, json.loads(result.stdout))

    def test_help_prints_only_usage(self) -> None:
        result = self.run_wrapper("help")

        self.assert_success(result)
        self.assertIn("Usage:", result.stdout)
        self.assertNotIn("CLEANUP", result.stdout + result.stderr)

    def test_dry_run_commands_stay_on_stdout(self) -> None:
        result = self.run_wrapper("plan", "dev", "--dry-run")

        self.assert_success(result)
        self.assertIn("$ terraform plan", result.stdout)
        self.assertNotIn("PREFLIGHT", result.stdout)


class DiagnosticsTests(WrapperTestCase):
    def test_doctor_accepts_root_relative_override(self) -> None:
        result = self.run_wrapper(
            "doctor", "dev", "--tfvars", "overrides/custom.tfvars"
        )

        self.assert_success(result)
        self.assertIn("overrides/custom.tfvars", result.stderr)

    def test_doctor_reports_missing_override(self) -> None:
        result = self.run_wrapper(
            "doctor", "dev", "--tfvars", "overrides/missing.tfvars"
        )

        self.assert_failure(result)
        self.assertIn("overrides/missing.tfvars", result.stderr)

    def test_debug_bundle_lists_the_files_plan_uses(self) -> None:
        self.write("env/dev/a.tfvars")

        result = self.run_wrapper(
            "debug-bundle", "dev", "--tfvars", "overrides/custom.tfvars"
        )

        self.assert_success(result)
        bundles = list(self.tmpdir.glob("terraform-debug.*"))
        self.assertEqual(1, len(bundles))
        listed = (bundles[0] / "var-files.txt").read_text(encoding="utf-8").split()
        self.assertEqual(
            [
                f"{self.root}/env/dev/a.tfvars",
                f"{self.root}/env/dev/terraform.tfvars",
                f"{self.root}/overrides/custom.tfvars",
            ],
            listed,
        )


class DetailedExitCodeTests(WrapperTestCase):
    def run_plan(self, *args: str, status: str) -> subprocess.CompletedProcess[str]:
        return self.run_wrapper(
            "plan",
            "dev",
            *args,
            extra_env={
                "FAKE_TERRAFORM_FAIL_ON": "plan",
                "FAKE_TERRAFORM_FAIL_STATUS": status,
            },
        )

    def test_changes_present_exit_code_is_not_a_failure(self) -> None:
        result = self.run_plan("-detailed-exitcode", status="2")

        self.assertEqual(2, result.returncode, result.stderr)
        self.assertIn("CHANGES PRESENT", result.stderr)
        self.assertNotIn("FAILED", result.stderr)

    def test_detailed_exitcode_error_is_a_failure(self) -> None:
        result = self.run_plan("-detailed-exitcode", status="1")

        self.assertEqual(1, result.returncode)
        self.assertIn("FAILED", result.stderr)

    def test_plan_exit_two_is_changes_even_without_explicit_flag(self) -> None:
        result = self.run_plan(status="2")

        self.assertEqual(2, result.returncode)
        self.assertIn("CHANGES PRESENT", result.stderr)
        self.assertNotIn("FAILED", result.stderr)

    def test_non_plan_exit_two_is_still_a_failure(self) -> None:
        result = self.run_wrapper(
            "output",
            "noenv",
            extra_env={
                "FAKE_TERRAFORM_FAIL_ON": "output",
                "FAKE_TERRAFORM_FAIL_STATUS": "2",
            },
        )

        self.assertEqual(2, result.returncode)
        self.assertIn("FAILED", result.stderr)

    def test_summary_continues_after_plan_changes(self) -> None:
        result = self.run_wrapper(
            "summ",
            "dev",
            "-detailed-exitcode",
            "--summary-format",
            "json",
            extra_env={
                "FAKE_TERRAFORM_FAIL_ON": "plan",
                "FAKE_TERRAFORM_FAIL_STATUS": "2",
            },
        )

        self.assertEqual(2, result.returncode)
        self.assertTrue(
            result.stdout.strip(), "The summary must be emitted after plan changes"
        )
        self.assertEqual({"create": 1}, json.loads(result.stdout))
        self.assertIn("CHANGES PRESENT", result.stderr)
        self.assertNotIn("FAILED", result.stderr)
        self.assertEqual({}, self.tree_digest(self.tmpdir))

    def test_summary_error_takes_precedence_over_plan_changes(self) -> None:
        summarizer = self.write("bin/tf-summarize", "#!/usr/bin/env bash\nexit 2\n")
        summarizer.chmod(0o755)
        result = self.run_wrapper(
            "summ",
            "dev",
            "-detailed-exitcode",
            extra_env={
                "PATH": f"{summarizer.parent}:{FAKES_DIR}:{os.environ['PATH']}",
                "FAKE_TERRAFORM_FAIL_ON": "plan",
                "FAKE_TERRAFORM_FAIL_STATUS": "2",
            },
        )

        self.assertEqual(2, result.returncode)
        self.assertIn("FAILED", result.stderr)
        self.assertNotIn("CHANGES PRESENT", result.stderr)
        self.assertEqual({}, self.tree_digest(self.tmpdir))


if __name__ == "__main__":
    unittest.main()
