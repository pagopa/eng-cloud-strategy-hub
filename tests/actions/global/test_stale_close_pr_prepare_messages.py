from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = ROOT / "actions/global/stale-close-pr/scripts/prepare_messages.py"


def load_module(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load module from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


prepare_messages = load_module(SCRIPT_PATH, "stale_close_prepare_messages")


class PrepareMessagesTests(unittest.TestCase):
    def test_default_messages_include_stale_and_close_windows(self) -> None:
        stale_message = prepare_messages.build_stale_message("", 25, 5)
        close_message = prepare_messages.build_close_message("", 5)

        self.assertIn("25 days", stale_message)
        self.assertIn("closed in 5 days", stale_message)
        self.assertIn("after 5 days", close_message)

    def test_days_before_close_minus_one_disables_close_message(self) -> None:
        stale_message = prepare_messages.build_stale_message("", 30, -1)
        close_message = prepare_messages.build_close_message("", -1)

        self.assertIn("will not be automatically closed", stale_message)
        self.assertEqual(
            "Automatic close is disabled for this pull request.", close_message
        )

    def test_custom_messages_are_preserved(self) -> None:
        self.assertEqual(
            "custom stale", prepare_messages.build_stale_message("custom stale", 25, 5)
        )
        self.assertEqual(
            "custom close", prepare_messages.build_close_message("custom close", 5)
        )

    def test_validate_inputs_rejects_invalid_boolean(self) -> None:
        with self.assertRaisesRegex(
            ValueError, "EXEMPT_DRAFT_PR_INPUT must be 'true' or 'false'"
        ):
            prepare_messages.validate_inputs(
                {
                    "DAYS_BEFORE_STALE_INPUT": "25",
                    "DAYS_BEFORE_CLOSE_INPUT": "5",
                    "OPERATIONS_PER_RUN_INPUT": "30",
                    "EXEMPT_DRAFT_PR_INPUT": "maybe",
                    "REMOVE_STALE_WHEN_UPDATED_INPUT": "true",
                    "ASCENDING_INPUT": "false",
                    "DELETE_BRANCH_INPUT": "false",
                }
            )

    def test_validate_inputs_accepts_default_scalars(self) -> None:
        days_before_stale, days_before_close = prepare_messages.validate_inputs(
            {
                "DAYS_BEFORE_STALE_INPUT": "25",
                "DAYS_BEFORE_CLOSE_INPUT": "5",
                "OPERATIONS_PER_RUN_INPUT": "30",
                "EXEMPT_DRAFT_PR_INPUT": "true",
                "REMOVE_STALE_WHEN_UPDATED_INPUT": "true",
                "ASCENDING_INPUT": "false",
                "DELETE_BRANCH_INPUT": "false",
            }
        )

        self.assertEqual(25, days_before_stale)
        self.assertEqual(5, days_before_close)


if __name__ == "__main__":
    unittest.main()
