"""Tests for asc.py's beta-description command: the exit status follows the API's answer and the read-back.

Run: python3 soqushield/scripts/test_asc.py
"""
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402

LOCALIZATIONS = {"data": [{"id": "loc-1", "attributes": {"locale": "en-US", "description": "old"}}]}


def fake_req(answers):
    """A req() that answers each method from a table and records every call."""
    calls = []

    def req(method, path, body=None):
        calls.append((method, path, body))
        return answers[method]

    return req, calls


class BetaDescriptionTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8")
        tmp.write("Mainnet text\n")
        tmp.close()
        self.path = tmp.name
        self.addCleanup(os.unlink, self.path)
        self.addCleanup(setattr, asc, "req", asc.req)

    def run_command(self, answers):
        asc.req, calls = fake_req(answers)
        out = io.StringIO()
        with redirect_stdout(out):
            code = asc.beta_description(self.path)
        return code, out.getvalue(), calls

    def test_equal_read_back_exits_zero(self):
        patched = {"data": {"attributes": {"description": "Mainnet text"}}}
        code, out, calls = self.run_command({"GET": (200, LOCALIZATIONS), "PATCH": (200, patched)})
        self.assertEqual(code, 0)
        self.assertIn("read back equal", out)
        self.assertEqual(calls[1][0], "PATCH")
        self.assertEqual(calls[1][1], "/v1/betaAppLocalizations/loc-1")
        self.assertEqual(calls[1][2]["data"]["attributes"]["description"], "Mainnet text")

    def test_rejected_patch_exits_nonzero_with_the_error(self):
        rejected = {"errors": [{"code": "STATE_ERROR", "detail": "The resource is locked"}]}
        code, out, _ = self.run_command({"GET": (200, LOCALIZATIONS), "PATCH": (409, rejected)})
        self.assertNotEqual(code, 0)
        self.assertIn("409", out)
        self.assertIn("STATE_ERROR", out)

    def test_mismatched_read_back_exits_nonzero(self):
        unchanged = {"data": {"attributes": {"description": "old"}}}
        code, out, _ = self.run_command({"GET": (200, LOCALIZATIONS), "PATCH": (200, unchanged)})
        self.assertNotEqual(code, 0)
        self.assertIn("differs", out)

    def test_failed_listing_exits_nonzero_before_any_patch(self):
        code, out, calls = self.run_command({"GET": (401, {"errors": [{"code": "NOT_AUTHORIZED"}]}), "PATCH": (200, {})})
        self.assertNotEqual(code, 0)
        self.assertIn("401", out)
        self.assertEqual([c[0] for c in calls], ["GET"])

    def test_missing_locale_exits_nonzero_before_any_patch(self):
        code, _, calls = self.run_command({"GET": (200, {"data": []}), "PATCH": (200, {})})
        self.assertNotEqual(code, 0)
        self.assertEqual([c[0] for c in calls], ["GET"])

    def test_length_outside_the_limit_is_refused_before_any_request(self):
        with open(self.path, "w", encoding="utf-8") as f:
            f.write("x" * 4001)
        code, _, calls = self.run_command({"GET": (200, LOCALIZATIONS), "PATCH": (200, {})})
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
