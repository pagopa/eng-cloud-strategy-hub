#!/usr/bin/env python3
"""Purpose: Simulate selected GitHub Actions checks on a local workstation.

Usage examples:
  python3 tools/validate_repo_locally/validate_repo_locally.py
  python3 tools/validate_repo_locally/validate_repo_locally.py --interactive
  python3 tools/validate_repo_locally/validate_repo_locally.py --skip pre-commit
  python3 tools/validate_repo_locally/validate_repo_locally.py --only terraform-wrapper-tests

Dependency decision note:
- Candidates: standard library argparse/subprocess, Questionary, Rich.
- Final choice: standard library for the default execution path, Questionary for
  the optional interactive selector.
- Why: default runs must stay dependency-light and CI-safe, while the
  interactive mode benefits from a purpose-built checkbox prompt.
"""

from __future__ import annotations

import argparse
import importlib
import os
import shlex
import shutil
import stat
import subprocess
import sys
import time
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

ACTIONLINT_PACKAGE = "github.com/rhysd/actionlint/cmd/actionlint@v1.7.12"
PRE_COMMIT_CONFIG = ".pre-commit-config.yaml"
PRE_COMMIT_IMAGE = (
    "ghcr.io/antonbabenko/pre-commit-terraform:v1.105.0"
    "@sha256:4ef4b8323b27fc263535ad88c9d2f20488fcb3b520258e5e7f0553ed5f6692b5"
)
DEFAULT_TMP_DIR = "tmp/validate-repo-locally"
SHELL_TARGET_ROOTS = (
    ".github/scripts",
    "scripts",
    "tests/scripts",
    "tools",
    "validate-repo-locally.sh",
)
TERRAFORM_WRAPPER_TARGETS = (
    "scripts/aws/terraform.sh",
    "scripts/azure/terraform.sh",
    "scripts/gcp/terraform.sh",
    "tests/scripts/terraform_wrappers/lib/assertions.sh",
    "tests/scripts/terraform_wrappers/run.sh",
    "tests/scripts/terraform_wrappers/fakes/terraform",
    "tests/scripts/terraform_wrappers/fakes/tf-summarize",
    "tests/scripts/terraform_wrappers/fakes/az",
    "tests/scripts/terraform_wrappers/fakes/aws",
    "tests/scripts/terraform_wrappers/fakes/gcloud",
    "tests/scripts/terraform_wrappers/fakes/tflist",
)
STEP_ALIASES = {
    "code-analysis": (
        "actionlint",
        "shell-static-analysis",
        "copilot-entrypoints",
    ),
    "precommit": ("pre-commit",),
    "terraform": ("terraform-wrapper-tests",),
}
INTERACTIVE_REQUIREMENTS = "tools/validate_repo_locally/requirements.txt"


@dataclass(frozen=True)
class Step:
    """A local simulation unit mapped to a GitHub Actions job or job family."""

    step_id: str
    workflow: str
    title: str
    run: Callable[[RunnerContext], int]


@dataclass(frozen=True)
class StepOutcome:
    """Execution result for one selected step."""

    step: Step
    exit_code: int
    duration_seconds: float


@dataclass(frozen=True)
class RunnerContext:
    """Runtime state shared by local simulation steps."""

    root: Path
    tmp_dir: Path
    dry_run: bool
    console: Console


@dataclass(frozen=True)
class DirectorySnapshot:
    """A restorable snapshot for a directory that local checks may rewrite."""

    source: Path
    snapshot: Path
    existed: bool


class Console:
    """Small operator-facing console with color-aware emoji logs."""

    def __init__(self, use_color: bool) -> None:
        self.use_color = use_color

    def title(self, message: str) -> None:
        print()
        print(self._style("=" * 72, "36"))
        print(self._style(message, "1;36"))
        print(self._style("=" * 72, "36"))

    def info(self, message: str) -> None:
        print(f"ℹ️  {message}")

    def warn(self, message: str) -> None:
        print(self._style(f"⚠️  {message}", "33"))

    def error(self, message: str) -> None:
        print(self._style(f"❌ {message}", "31"), file=sys.stderr)

    def success(self, message: str) -> None:
        print(self._style(f"✅ {message}", "32"))

    def command(self, args: Sequence[str | Path]) -> None:
        rendered = shlex.join(str(arg) for arg in args)
        print(self._style(f"   $ {rendered}", "2"))

    def step_start(self, step: Step) -> None:
        print()
        print(self._style(f"▶ {step.title}", "1"))
        print(f"   workflow: {step.workflow}")
        print(f"   id: {step.step_id}")

    def step_result(self, outcome: StepOutcome) -> None:
        seconds = f"{outcome.duration_seconds:.1f}s"
        if outcome.exit_code == 0:
            self.success(f"{outcome.step.title} passed in {seconds}")
            return
        self.error(
            f"{outcome.step.title} failed with exit code "
            f"{outcome.exit_code} after {seconds}"
        )

    def _style(self, value: str, code: str) -> str:
        if not self.use_color:
            return value
        return f"\033[{code}m{value}\033[0m"


def build_steps() -> list[Step]:
    return [
        Step(
            "actionlint",
            ".github/workflows/_code-analysis.yml",
            "Workflow static analysis with actionlint",
            run_actionlint,
        ),
        Step(
            "shell-static-analysis",
            ".github/workflows/_code-analysis.yml",
            "Shell syntax and ShellCheck analysis",
            run_shell_static_analysis,
        ),
        Step(
            "copilot-entrypoints",
            ".github/workflows/_code-analysis.yml",
            "Copilot customization entrypoint smoke tests",
            run_copilot_entrypoints,
        ),
        Step(
            "pre-commit",
            ".github/workflows/_pre-commit.yml",
            "Containerized pre-commit suite",
            run_pre_commit,
        ),
        Step(
            "terraform-wrapper-tests",
            ".github/workflows/terraform-wrapper-tests.yml",
            "Terraform wrapper syntax, lint, and simulation suite",
            run_terraform_wrapper_tests,
        ),
    ]


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run local simulations for selected GitHub Actions checks."
    )
    parser.add_argument(
        "--root",
        default=".",
        help="Repository root or any path inside it. Defaults to the current directory.",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        help="Run only a step or alias. Repeat or comma-separate values.",
    )
    parser.add_argument(
        "--skip",
        action="append",
        default=[],
        help="Skip a step or alias. Repeat or comma-separate values.",
    )
    parser.add_argument(
        "--yes",
        "--no-prompt",
        action="store_true",
        dest="no_prompt",
        help="Compatibility flag for non-interactive runs. Incompatible with --interactive.",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Open an interactive checkbox menu to choose which checks to run.",
    )
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Stop after the first failing selected check.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without executing them.",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available steps and aliases, then exit.",
    )
    parser.add_argument(
        "--tmp-dir",
        default=DEFAULT_TMP_DIR,
        help="Local runtime/cache directory. Defaults to tmp/validate-repo-locally.",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI color output.",
    )
    args = parser.parse_args(argv)
    validate_args(parser, args)
    return args


def validate_args(parser: argparse.ArgumentParser, args: argparse.Namespace) -> None:
    if args.interactive and args.no_prompt:
        parser.error("--interactive cannot be combined with --yes/--no-prompt.")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    use_color = (
        sys.stdout.isatty() and not args.no_color and "NO_COLOR" not in os.environ
    )
    console = Console(use_color)
    root = find_repo_root(Path(args.root).resolve())
    tmp_dir = resolve_runtime_path(root, args.tmp_dir)
    steps = build_steps()

    if args.list:
        print_step_catalog(steps, console)
        return 0

    selected_steps = select_steps(steps, args.only, args.skip)
    selected_steps = prompt_for_steps(
        selected_steps,
        interactive=args.interactive,
        console=console,
    )
    if not selected_steps:
        console.warn("No checks selected.")
        return 0

    tmp_dir.mkdir(parents=True, exist_ok=True)
    context = RunnerContext(
        root=root, tmp_dir=tmp_dir, dry_run=args.dry_run, console=console
    )

    console.title("Local GitHub Actions Simulator")
    console.info(f"Repository: {root}")
    console.info(f"Runtime dir: {tmp_dir}")
    console.info("Selected checks:")
    for step in selected_steps:
        print(f"   - {step.step_id}: {step.title}")

    outcomes = run_steps(selected_steps, context, args.fail_fast)
    return print_summary(outcomes, console)


def find_repo_root(start: Path) -> Path:
    current = start if start.is_dir() else start.parent
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists() and (candidate / "AGENTS.md").is_file():
            return candidate
    raise SystemExit(f"❌ Could not find repository root from {start}")


def resolve_runtime_path(root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def print_step_catalog(steps: Sequence[Step], console: Console) -> None:
    console.title("Available Local Checks")
    for step in steps:
        print(f"{step.step_id:26} {step.workflow}")
        print(f"{'':26} {step.title}")
    print()
    console.info("Aliases:")
    for alias, step_ids in STEP_ALIASES.items():
        print(f"   {alias}: {', '.join(step_ids)}")


def split_filters(values: Sequence[str]) -> list[str]:
    filters: list[str] = []
    for value in values:
        filters.extend(part.strip() for part in value.split(",") if part.strip())
    return filters


def expand_filters(values: Sequence[str], steps: Sequence[Step]) -> set[str]:
    available = {step.step_id for step in steps}
    expanded: set[str] = set()
    for value in split_filters(values):
        if value in available:
            expanded.add(value)
            continue
        if value in STEP_ALIASES:
            expanded.update(STEP_ALIASES[value])
            continue
        valid_values = sorted(available | set(STEP_ALIASES))
        raise SystemExit(
            "❌ Unknown check or alias "
            f"'{value}'. Valid values: {', '.join(valid_values)}"
        )
    return expanded


def select_steps(
    steps: Sequence[Step], only_values: Sequence[str], skip_values: Sequence[str]
) -> list[Step]:
    only = expand_filters(only_values, steps)
    skip = expand_filters(skip_values, steps)
    selected = [step for step in steps if not only or step.step_id in only]
    return [step for step in selected if step.step_id not in skip]


def prompt_for_steps(
    steps: Sequence[Step], *, interactive: bool, console: Console
) -> list[Step]:
    if not steps:
        return []

    if not interactive:
        return list(steps)

    if not sys.stdin.isatty():
        raise SystemExit("❌ --interactive requires an interactive terminal.")

    questionary = import_questionary()
    choices = [
        questionary.Choice(
            title=f"{step.step_id} - {step.title}",
            value=step.step_id,
            checked=True,
        )
        for step in steps
    ]

    console.title("Choose Checks")
    try:
        selected_ids = questionary.checkbox(
            "Select the local checks to run",
            choices=choices,
            instruction="Space toggles, Enter confirms",
        ).ask()
    except KeyboardInterrupt as error:
        raise SystemExit(130) from error

    if selected_ids is None:
        raise SystemExit(130)

    selected_lookup = set(selected_ids)
    return [step for step in steps if step.step_id in selected_lookup]


def import_questionary():
    try:
        return importlib.import_module("questionary")
    except ModuleNotFoundError as error:
        raise SystemExit(
            "❌ Missing interactive dependency: questionary.\n"
            "Run ./validate-repo-locally.sh --interactive so the wrapper can "
            f"install {INTERACTIVE_REQUIREMENTS}."
        ) from error


def run_steps(
    steps: Sequence[Step], context: RunnerContext, fail_fast: bool
) -> list[StepOutcome]:
    outcomes: list[StepOutcome] = []
    for step in steps:
        context.console.step_start(step)
        started = time.monotonic()
        exit_code = step.run(context)
        outcome = StepOutcome(
            step=step,
            exit_code=exit_code,
            duration_seconds=time.monotonic() - started,
        )
        outcomes.append(outcome)
        context.console.step_result(outcome)
        if exit_code != 0 and fail_fast:
            context.console.warn("Stopping early because --fail-fast is enabled.")
            break
    return outcomes


def print_summary(outcomes: Sequence[StepOutcome], console: Console) -> int:
    console.title("Summary")
    failed = [outcome for outcome in outcomes if outcome.exit_code != 0]
    for outcome in outcomes:
        status = "PASS" if outcome.exit_code == 0 else "FAIL"
        seconds = f"{outcome.duration_seconds:.1f}s"
        print(f"{status:4} {seconds:>8}  {outcome.step.step_id}")
    if failed:
        console.error(f"{len(failed)} check(s) failed.")
        return 1
    console.success("All selected local checks passed.")
    return 0


def run_command(
    context: RunnerContext,
    args: Sequence[str | Path],
    *,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
) -> int:
    context.console.command(args)
    if context.dry_run:
        return 0

    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    completed = subprocess.run(
        [str(arg) for arg in args],
        cwd=str(cwd or context.root),
        env=merged_env,
        check=False,
    )
    return completed.returncode


def run_actionlint(context: RunnerContext) -> int:
    workflow_files = sorted((context.root / ".github/workflows").glob("*.yml"))
    if not workflow_files:
        context.console.error("No .github/workflows/*.yml files found.")
        return 1

    actionlint = resolve_actionlint(context)
    if actionlint is None:
        return 1

    version_status = run_command(context, [actionlint, "-version"])
    if version_status != 0:
        return version_status
    return run_command(context, [actionlint, *workflow_files])


def resolve_actionlint(context: RunnerContext) -> Path | None:
    actionlint = shutil.which("actionlint")
    if actionlint:
        return Path(actionlint)

    go_binary = shutil.which("go")
    if not go_binary:
        context.console.error("Go is required to install actionlint locally.")
        return None

    gobin = context.tmp_dir / "bin"
    gobin.mkdir(parents=True, exist_ok=True)
    install_status = run_command(
        context,
        [go_binary, "install", ACTIONLINT_PACKAGE],
        env={"GOBIN": str(gobin)},
    )
    if install_status != 0:
        return None
    return gobin / "actionlint"


def run_shell_static_analysis(context: RunnerContext) -> int:
    targets = collect_shell_targets(context.root, SHELL_TARGET_ROOTS)
    if not targets:
        context.console.error("No shell analysis targets found.")
        return 1

    context.console.info("Shell targets:")
    for target in targets:
        print(f"   - {relative_to_root(context.root, target)}")

    for target in targets:
        status = run_command(context, ["bash", "-n", target])
        if status != 0:
            return status
    return run_shellcheck(context, targets, include_external_sources=True)


def collect_shell_targets(root: Path, target_roots: Iterable[str]) -> list[Path]:
    targets: list[Path] = []
    for target_root in target_roots:
        path = root / target_root
        if not path.exists():
            continue
        candidates = [path] if path.is_file() else path.rglob("*")
        for candidate in candidates:
            if candidate.name == ".gitkeep" or not candidate.is_file():
                continue
            if has_bash_shebang(candidate):
                targets.append(candidate)
    return sorted(targets, key=lambda item: relative_to_root(root, item))


def has_bash_shebang(path: Path) -> bool:
    with path.open("rb") as file:
        first_line = file.readline().decode("utf-8", "ignore").strip()
    return first_line in {"#!/usr/bin/env bash", "#!/bin/bash"}


def run_shellcheck(
    context: RunnerContext, targets: Sequence[Path], *, include_external_sources: bool
) -> int:
    if not shutil.which("shellcheck"):
        context.console.error(
            "Missing required binary: shellcheck. Install it locally "
            "or skip this check while iterating."
        )
        return 1
    args: list[str | Path] = ["shellcheck", "-s", "bash"]
    if include_external_sources:
        args.append("-x")
    args.extend(targets)
    return run_command(context, args)


def run_copilot_entrypoints(context: RunnerContext) -> int:
    commands = (
        ["bash", ".github/scripts/bootstrap-copilot-config.sh", "--help"],
        ["bash", ".github/scripts/validate-copilot-customizations.sh", "--help"],
    )
    for command in commands:
        status = run_command(context, command)
        if status != 0:
            return status
    return 0


def run_pre_commit(context: RunnerContext) -> int:
    if not shutil.which("docker"):
        context.console.error("Missing required binary: docker.")
        return 1

    cache_dir = context.tmp_dir / "pre-commit-cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    commands = (
        ["docker", "pull", PRE_COMMIT_IMAGE],
        [
            "docker",
            "run",
            "--rm",
            "--entrypoint",
            "cat",
            PRE_COMMIT_IMAGE,
            "/usr/bin/tools_versions_info",
        ],
        build_pre_commit_run_command(context.root, cache_dir),
    )
    env = {"TF_INPUT": "0", "TF_IN_AUTOMATION": "1"}
    for command in commands:
        status = run_command(context, command, env=env)
        if status != 0:
            return status
    return 0


def build_pre_commit_run_command(root: Path, cache_dir: Path) -> list[str]:
    user_id = "1000:1000"
    if hasattr(os, "getuid") and hasattr(os, "getgid"):
        user_id = f"{os.getuid()}:{os.getgid()}"

    return [
        "docker",
        "run",
        "--rm",
        "-e",
        f"USERID={user_id}",
        "-e",
        "PRE_COMMIT_HOME=/pre-commit-cache",
        "-e",
        "TF_INPUT",
        "-e",
        "TF_IN_AUTOMATION",
        "-v",
        f"{cache_dir}:/pre-commit-cache",
        "-v",
        f"{root}:/lint",
        "-w",
        "/lint",
        PRE_COMMIT_IMAGE,
        "run",
        "--all-files",
        "--config",
        PRE_COMMIT_CONFIG,
        "--verbose",
        "--show-diff-on-failure",
        "--color",
        "always",
    ]


def run_terraform_wrapper_tests(context: RunnerContext) -> int:
    targets = resolve_paths(context.root, TERRAFORM_WRAPPER_TARGETS)
    if targets is None:
        return 1

    syntax_status = run_command(context, ["bash", "-n", *targets])
    if syntax_status != 0:
        return syntax_status

    shellcheck_status = run_shellcheck(
        context,
        targets,
        include_external_sources=False,
    )
    if shellcheck_status != 0:
        return shellcheck_status

    original_modes = read_file_modes(targets)
    logs_snapshot = snapshot_directory(
        context.root / "tests/scripts/terraform_wrappers/logs",
        context.tmp_dir / "snapshots/terraform-wrapper-logs",
        context.dry_run,
    )
    suite_status = 1
    try:
        chmod_status = run_command(context, ["chmod", "+x", *targets])
        if chmod_status != 0:
            return chmod_status
        suite_status = run_command(
            context, ["bash", "tests/scripts/terraform_wrappers/run.sh"]
        )
        return suite_status
    finally:
        restore_file_modes(original_modes, context.dry_run)
        if suite_status == 0:
            restore_directory_snapshot(logs_snapshot, context.dry_run)


def resolve_paths(root: Path, relative_paths: Sequence[str]) -> list[Path] | None:
    paths = [root / value for value in relative_paths]
    missing = [path for path in paths if not path.exists()]
    if missing:
        for path in missing:
            print(
                f"❌ Missing expected file: {relative_to_root(root, path)}",
                file=sys.stderr,
            )
        return None
    return paths


def read_file_modes(paths: Sequence[Path]) -> dict[Path, int]:
    return {path: stat.S_IMODE(path.stat().st_mode) for path in paths}


def restore_file_modes(modes: dict[Path, int], dry_run: bool) -> None:
    if dry_run:
        return
    for path, mode in modes.items():
        if path.exists():
            path.chmod(mode)


def snapshot_directory(
    source: Path, snapshot: Path, dry_run: bool
) -> DirectorySnapshot:
    if dry_run:
        return DirectorySnapshot(
            source=source, snapshot=snapshot, existed=source.exists()
        )

    if snapshot.exists():
        shutil.rmtree(snapshot)
    snapshot.parent.mkdir(parents=True, exist_ok=True)

    if not source.exists():
        return DirectorySnapshot(source=source, snapshot=snapshot, existed=False)

    shutil.copytree(source, snapshot)
    return DirectorySnapshot(source=source, snapshot=snapshot, existed=True)


def restore_directory_snapshot(snapshot: DirectorySnapshot, dry_run: bool) -> None:
    if dry_run:
        return

    if snapshot.source.exists():
        shutil.rmtree(snapshot.source)
    if snapshot.existed:
        shutil.copytree(snapshot.snapshot, snapshot.source)
    if snapshot.snapshot.exists():
        shutil.rmtree(snapshot.snapshot)


def relative_to_root(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


if __name__ == "__main__":
    raise SystemExit(main())
