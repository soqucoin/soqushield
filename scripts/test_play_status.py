"""Tests for play_status.py's highest-version-code reading, which the release workflow uses to skip an
upload whose build number is already on a track.

Run: python3 scripts/test_play_status.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_status  # noqa: E402


class MaxVersionCodeTests(unittest.TestCase):
    def test_no_tracks_is_zero(self):
        self.assertEqual(play_status.max_version_code({}), 0)

    def test_empty_releases_is_zero(self):
        self.assertEqual(play_status.max_version_code({"tracks": [{"track": "beta", "releases": [{"status": "draft"}]}]}), 0)

    def test_highest_across_tracks(self):
        tracks = {"tracks": [
            {"track": "production", "releases": [{"versionCodes": ["31"]}]},
            {"track": "internal", "releases": [{"versionCodes": ["31"]}, {"versionCodes": ["33", "32"]}]},
            {"track": "alpha"},
        ]}
        self.assertEqual(play_status.max_version_code(tracks), 33)


if __name__ == "__main__":
    unittest.main()
