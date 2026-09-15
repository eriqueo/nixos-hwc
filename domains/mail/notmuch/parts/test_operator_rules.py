#!/usr/bin/env python3
"""Regression tests for the mutable mail-rule ledger and notmuch adapter."""

from __future__ import annotations

import importlib.util
import io
import os
import sys
import tempfile
import unittest
from email.message import EmailMessage
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(
    os.environ.get("MAIL_RULE_SOURCE", Path(__file__).with_name("operator-rules.py"))
)
SPEC = importlib.util.spec_from_file_location("operator_rules", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
operator_rules = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = operator_rules
SPEC.loader.exec_module(operator_rules)


class LedgerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db_path = Path(self.temp.name) / "state" / "rules.sqlite"
        self.conn = operator_rules.open_ledger(self.db_path)
        self.addCleanup(self.conn.close)

    @staticmethod
    def plan(
        sender: str = "offers@example.com",
        disposition: str = "archive",
        folder: str = "hwc",
    ):
        return operator_rules.RulePlan(
            sender=sender,
            display_name="Example Sender",
            disposition=disposition,
            folder_tag=folder,
            source_message_id="fixture-1@example.com",
            example_subject="Example subject",
        )

    def test_ledger_is_private_versioned_and_idempotent(self) -> None:
        rule_id, changed = operator_rules.set_rule(
            self.conn, self.plan(), recorded_at="2026-09-15T12:00:00+00:00"
        )
        self.assertTrue(changed)
        self.assertEqual(rule_id, operator_rules.rule_id_for("offers@example.com"))
        _, changed = operator_rules.set_rule(
            self.conn, self.plan(), recorded_at="2026-09-15T12:01:00+00:00"
        )
        self.assertFalse(changed)
        self.assertEqual(
            self.conn.execute("SELECT count(*) FROM rule_events").fetchone()[0], 1
        )
        self.assertEqual(
            self.conn.execute("PRAGMA user_version").fetchone()[0],
            operator_rules.SCHEMA_VERSION,
        )
        self.assertEqual(self.db_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.db_path.parent.stat().st_mode & 0o777, 0o700)

    def test_disable_preserves_history_and_rule_can_be_reactivated(self) -> None:
        operator_rules.set_rule(
            self.conn, self.plan(), recorded_at="2026-09-15T12:00:00+00:00"
        )
        self.assertTrue(
            operator_rules.disable_rule(
                self.conn,
                "offers@example.com",
                recorded_at="2026-09-15T12:01:00+00:00",
            )
        )
        self.assertEqual(operator_rules.active_rules(self.conn), [])
        _, changed = operator_rules.set_rule(
            self.conn, self.plan(), recorded_at="2026-09-15T12:02:00+00:00"
        )
        self.assertTrue(changed)
        self.assertEqual(len(operator_rules.active_rules(self.conn)), 1)
        self.assertEqual(
            self.conn.execute("SELECT count(*) FROM rule_events").fetchone()[0], 3
        )

    def test_active_rule_limit_rejects_instead_of_growing_unbounded(self) -> None:
        with mock.patch.object(operator_rules, "MAX_ACTIVE_RULES", 1):
            operator_rules.set_rule(
                self.conn,
                self.plan(),
                recorded_at="2026-09-15T12:00:00+00:00",
            )
            with self.assertRaisesRegex(operator_rules.RuleError, "safety limit"):
                operator_rules.set_rule(
                    self.conn,
                    self.plan(sender="other@example.com"),
                    recorded_at="2026-09-15T12:01:00+00:00",
                )

    def test_corrupt_store_fails_loudly(self) -> None:
        self.conn.close()
        self.db_path.write_bytes(b"not sqlite")
        with self.assertRaisesRegex(operator_rules.RuleError, "Cannot open"):
            operator_rules.open_ledger(self.db_path)


class MessageTest(unittest.TestCase):
    @staticmethod
    def message() -> bytes:
        message = EmailMessage()
        message["From"] = "Offers Team <Offers@Example.COM>"
        message["To"] = "eric@example.net"
        message["Subject"] = "A useful example"
        message["Message-ID"] = "<fixture-1@example.com>"
        message.set_content("Body")
        return message.as_bytes()

    def test_parse_requires_one_exact_sender_and_normalizes_it(self) -> None:
        parsed = operator_rules.parse_message(self.message())
        self.assertEqual(parsed.sender, "offers@example.com")
        self.assertEqual(parsed.display_name, "Offers Team")
        self.assertEqual(parsed.message_id, "fixture-1@example.com")

    def test_mbox_or_multiple_message_input_is_rejected(self) -> None:
        with self.assertRaisesRegex(operator_rules.RuleError, "More than one"):
            operator_rules.parse_message(b"From sender@example.com\n" + self.message())

    def test_invalid_sender_is_rejected(self) -> None:
        message = EmailMessage()
        message["From"] = "Undisclosed recipients:;"
        message.set_content("Body")
        with self.assertRaisesRegex(operator_rules.RuleError, "exactly one"):
            operator_rules.parse_message(message.as_bytes())

    def test_oversized_message_is_rejected_before_parsing(self) -> None:
        with mock.patch.object(operator_rules, "MAX_MESSAGE_BYTES", 4):
            with self.assertRaisesRegex(operator_rules.RuleError, "review limit"):
                operator_rules.parse_message(b"12345")

    def test_folder_inference_has_stable_precedence(self) -> None:
        self.assertEqual(operator_rules.infer_folder({"family", "datax", "hwc"}), "datax")
        self.assertEqual(operator_rules.infer_folder({"family", "hwc"}), "family")
        self.assertEqual(operator_rules.infer_folder({"office"}), "hwc")
        self.assertEqual(operator_rules.infer_folder({"finance"}), "")


class NotmuchAdapterTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.conn = operator_rules.open_ledger(
            Path(self.temp.name) / "state" / "rules.sqlite"
        )
        self.addCleanup(self.conn.close)

    def add(self, sender: str, disposition: str, folder: str) -> None:
        operator_rules.set_rule(
            self.conn,
            operator_rules.RulePlan(
                sender=sender,
                display_name="",
                disposition=disposition,
                folder_tag=folder,
                source_message_id="fixture@example.com",
                example_subject="Fixture",
            ),
            recorded_at="2026-09-15T12:00:00+00:00",
        )

    def test_rules_are_grouped_and_destructive_groups_protect_keep(self) -> None:
        self.add("one@example.com", "archive", "hwc")
        self.add("two@example.com", "archive", "hwc")
        self.add("family@example.com", "now", "family")
        calls = []

        def capture(_notmuch, args):
            calls.append(args)
            return mock.Mock(returncode=0, stdout="", stderr="")

        with mock.patch.object(operator_rules, "_run_notmuch", side_effect=capture):
            groups = operator_rules.apply_active_rules(self.conn, "/bin/notmuch")

        self.assertEqual(groups, 2)
        self.assertEqual(len(calls), 2)
        archive = next(args for args in calls if "+archive" in args)
        now = next(args for args in calls if "+queue" in args)
        self.assertIn("NOT tag:keep", archive[-1])
        self.assertNotIn("NOT tag:keep", now[-1])
        self.assertIn('from:"one@example.com"', archive[-1])
        self.assertIn('from:"two@example.com"', archive[-1])
        self.assertIn("+family", now)

    def test_kept_current_message_refuses_destructive_move(self) -> None:
        plan = operator_rules.RulePlan(
            sender="offers@example.com",
            display_name="",
            disposition="trash",
            folder_tag="",
            source_message_id="fixture@example.com",
            example_subject="Fixture",
        )
        count = mock.Mock(returncode=0, stdout="1\n", stderr="")
        with mock.patch.object(operator_rules, "_run_notmuch", return_value=count) as run:
            changed, message = operator_rules.apply_current(plan, "/bin/notmuch")
        self.assertFalse(changed)
        self.assertIn("protected by keep", message)
        self.assertEqual(run.call_count, 1)

    def test_rule_listing_is_human_readable(self) -> None:
        self.add("offers@example.com", "trash", "")
        output = io.StringIO()
        operator_rules.print_rules(self.conn, output)
        self.assertIn("STATE", output.getvalue())
        self.assertIn("offers@example.com", output.getvalue())
        self.assertIn("trash", output.getvalue())


if __name__ == "__main__":
    unittest.main()
