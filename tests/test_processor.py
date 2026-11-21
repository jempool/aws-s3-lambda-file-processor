import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from processor import process_file  # noqa: E402


def as_bytes(data):
    return json.dumps(data).encode("utf-8")


class ValidFileTests(unittest.TestCase):
    def test_sample_file_is_summarized(self):
        body = (ROOT / "sample-data" / "transactions.json").read_bytes()

        summary = process_file(body)

        self.assertEqual(
            summary,
            {
                "status": "PROCESSED",
                "total_transactions": 3,
                "total_amount": 500,
                "average_amount": 166.67,
            },
        )

    def test_decimal_amounts_are_rounded_to_cents(self):
        body = as_bytes(
            [
                {"id": 1, "customer": "A", "amount": 10.10},
                {"id": 2, "customer": "B", "amount": 20.20},
            ]
        )

        summary = process_file(body)

        self.assertEqual(summary["total_amount"], 30.3)
        self.assertEqual(summary["average_amount"], 15.15)


class InvalidFileTests(unittest.TestCase):
    def assert_failed_with(self, body, *expected_errors):
        summary = process_file(body)
        self.assertEqual(summary["status"], "FAILED")
        self.assertEqual(summary["errors"], list(expected_errors))

    def test_malformed_json(self):
        self.assert_failed_with(b'[{"id": 1,', "File is not valid JSON")

    def test_non_utf8_content(self):
        self.assert_failed_with(b"\xff\xfe\x00", "File is not valid JSON")

    def test_top_level_must_be_a_list(self):
        self.assert_failed_with(
            as_bytes({"id": 1}), "File must contain a JSON array of transactions"
        )

    def test_empty_list(self):
        self.assert_failed_with(as_bytes([]), "File contains no transactions")

    def test_every_problem_is_reported(self):
        body = as_bytes(
            [
                {"id": 1, "customer": "A", "amount": 10},
                {"id": 2, "amount": 5},
                {"id": 3, "customer": "C", "amount": "ten"},
                "not an object",
                {"id": 5, "customer": "E", "amount": True},
            ]
        ).replace(b'"amount": 10}', b'"amount": NaN}')

        self.assert_failed_with(
            body,
            "Transaction 1: 'amount' must be a number",
            "Transaction 2: missing field 'customer'",
            "Transaction 3: 'amount' must be a number",
            "Transaction 4: must be a JSON object",
            "Transaction 5: 'amount' must be a number",
        )


if __name__ == "__main__":
    unittest.main()
