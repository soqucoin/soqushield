"""Tests for play_status.py: the highest-version-code reading, which the release workflow uses to skip
an upload whose build number is already on a track, and the store calls' behaviour on a transient
answer from Google.

Run: python3 scripts/test_play_status.py
"""
import contextlib
import io
import os
import sys
import unittest
import urllib.error
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_status  # noqa: E402


def http_error(code):
    return urllib.error.HTTPError("https://example.invalid", code, "unavailable", {}, io.BytesIO(b""))


class _Answer(io.BytesIO):
    """A response that works as a context manager, like urlopen's."""
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class CallRetryTests(unittest.TestCase):
    def test_a_transient_answer_is_retried_then_read(self):
        answers = [http_error(503), http_error(503), _Answer(b'{"ok": 1}')]
        waits = []

        def urlopen(req):
            a = answers.pop(0)
            if isinstance(a, Exception):
                raise a
            return a

        with mock.patch.object(play_status.urllib.request, "urlopen", urlopen), \
                mock.patch.object(play_status.time, "sleep", waits.append), \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(play_status.call("t", "GET", "/x"), {"ok": 1})
        self.assertEqual(waits, [2, 4], "two waits for two transient answers")
        self.assertEqual(answers, [], "every answer consumed")

    def test_a_lasting_or_other_error_raises(self):
        with mock.patch.object(play_status.time, "sleep", lambda s: None), \
                contextlib.redirect_stderr(io.StringIO()):
            with mock.patch.object(play_status.urllib.request, "urlopen",
                                   mock.Mock(side_effect=http_error(503))) as u:
                with self.assertRaises(urllib.error.HTTPError):
                    play_status.call("t", "GET", "/x")
                self.assertEqual(u.call_count, play_status.ATTEMPTS, "the last attempt raises")
            with mock.patch.object(play_status.urllib.request, "urlopen",
                                   mock.Mock(side_effect=http_error(404))) as u:
                with self.assertRaises(urllib.error.HTTPError):
                    play_status.call("t", "GET", "/x")
                self.assertEqual(u.call_count, 1, "a 404 is not retried")


class MainCleanupTests(unittest.TestCase):
    def test_a_failed_delete_of_the_read_only_edit_keeps_the_answer(self):
        def fake_call(tok, method, path, body=None):
            if method == "POST":
                return {"id": "e1"}
            if method == "GET":
                return {"tracks": [{"track": "internal", "releases": [{"versionCodes": ["32"]}]}]}
            raise http_error(503)

        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(play_status, "load_env", lambda: None), \
                mock.patch.object(play_status, "token", lambda: "t"), \
                mock.patch.object(play_status, "call", fake_call), \
                mock.patch.object(sys, "argv", ["play_status.py", "--max-code"]), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            play_status.main()
        self.assertEqual(out.getvalue().strip(), "32", "the read's answer stands")
        self.assertIn("e1", err.getvalue(), "the failed delete is said, with the edit's id")


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
