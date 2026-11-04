"""Tests for asc.py's main(): the exit status follows the API's answer, so release automation sees a
rejected write as a failure.

Run: python3 scripts/test_asc_main.py
"""
import io
import os
import sys
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402


class MainExitTests(unittest.TestCase):
    def setUp(self):
        self.addCleanup(setattr, asc, "req", asc.req)
        self.addCleanup(setattr, sys, "argv", sys.argv)

    def run_main(self, argv, status, body=None):
        asc.req = lambda method, path, body=None: (status, body or {})
        sys.argv = ["asc.py", *argv]
        with redirect_stdout(io.StringIO()):
            return asc.main()

    def test_submit_created_exits_zero(self):
        self.assertEqual(self.run_main(["submit", "build-1"], 201), 0)

    def test_submit_conflict_exits_one(self):
        self.assertEqual(self.run_main(["submit", "build-1"], 409, {"errors": [{"status": "409"}]}), 1)

    def test_attach_no_content_exits_zero(self):
        self.assertEqual(self.run_main(["attach", "build-1", "group-1"], 204), 0)

    def test_attach_forbidden_exits_one(self):
        self.assertEqual(self.run_main(["attach", "build-1", "group-1"], 403), 1)

    def test_whatsnew_rejected_exits_one(self):
        self.assertEqual(self.run_main(["whatsnew", "build-1", "text"], 422, {"data": []}), 1)

    def test_get_not_found_exits_one(self):
        self.assertEqual(self.run_main(["get", "/v1/nothing"], 404), 1)

    def test_build_lookup_exits_zero(self):
        self.assertEqual(self.run_main(["build", "32"], 200, {"data": []}), 0)

    def test_unknown_command_exits_two(self):
        self.assertEqual(self.run_main(["nonsense"], 200), 2)


if __name__ == "__main__":
    unittest.main()
