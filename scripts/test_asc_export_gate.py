"""Tests for asc_export_gate.py's beta-state rule: a build is attached only when its beta state is known
and is not MISSING_EXPORT_COMPLIANCE.

Run: python3 scripts/test_asc_export_gate.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_export_gate as gate  # noqa: E402


class BetaStateTests(unittest.TestCase):
    def test_no_detail_is_missing(self):
        self.assertTrue(gate.beta_state_missing([]))

    def test_null_state_is_missing(self):
        self.assertTrue(gate.beta_state_missing([{"internalBuildState": None, "externalBuildState": None}]))

    def test_absent_key_is_missing(self):
        self.assertTrue(gate.beta_state_missing([{"externalBuildState": "READY_FOR_BETA_TESTING"}]))

    def test_export_compliance_missing_is_missing(self):
        self.assertTrue(gate.beta_state_missing([{"internalBuildState": "MISSING_EXPORT_COMPLIANCE"}]))

    def test_one_bad_detail_among_good_ones_is_missing(self):
        self.assertTrue(gate.beta_state_missing([{"internalBuildState": "IN_BETA_TESTING"},
                                                 {"internalBuildState": None}]))

    def test_known_state_passes(self):
        self.assertFalse(gate.beta_state_missing([{"internalBuildState": "IN_BETA_TESTING",
                                                   "externalBuildState": "READY_FOR_BETA_TESTING"}]))


if __name__ == "__main__":
    unittest.main()
