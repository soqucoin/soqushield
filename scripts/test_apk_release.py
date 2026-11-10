"""Tests for apk_release.py: the certificate check that stands between a built APK and the Releases
page, and the three files a release carries.

Run: python3 scripts/test_apk_release.py
"""
import hashlib
import os
import pathlib
import sys
import tempfile
import types
import unittest
import zipfile
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apk_release  # noqa: E402

CERT = apk_release.SIGNING_CERT_SHA256
DEBUG = "f179209397e068e6f7556130bf842753a9bb795958871562e82b98b47a05c648"

# What build-tools 37 prints, and what the older build-tools print, for the same APK.
NEW_FORMAT = f"""V2 Signer: certificate DN: CN=Soqucoin Labs Inc, O=Soqucoin Labs, L=New York, ST=New York, C=US
V2 Signer: certificate SHA-256 digest: {CERT}
V2 Signer: certificate SHA-1 digest: 0472c6971ee92d99284a07b376134f3691029ea2
V2 Signer: certificate MD5 digest: 2fc21fce515e6c92729ecce43743143b
"""
OLD_FORMAT = f"""Signer #1 certificate DN: CN=Soqucoin Labs Inc, O=Soqucoin Labs, L=New York, ST=New York, C=US
Signer #1 certificate SHA-256 digest: {CERT}
Signer #1 certificate SHA-1 digest: 0472c6971ee92d99284a07b376134f3691029ea2
"""


def answer(stdout="", returncode=0, stderr=""):
    return lambda *a, **k: types.SimpleNamespace(stdout=stdout, stderr=stderr, returncode=returncode)


class CertificateTests(unittest.TestCase):
    def test_both_output_formats_are_read(self):
        self.assertEqual(apk_release.cert_digests(NEW_FORMAT), {CERT})
        self.assertEqual(apk_release.cert_digests(OLD_FORMAT), {CERT})

    def test_the_release_certificate_alone_passes(self):
        apk_release.check_cert(NEW_FORMAT)
        apk_release.check_cert(OLD_FORMAT)

    def test_another_certificate_is_refused(self):
        with self.assertRaises(apk_release.Refused) as raised:
            apk_release.check_cert(NEW_FORMAT.replace(CERT, DEBUG))
        self.assertIn(DEBUG, str(raised.exception))

    def test_a_second_certificate_beside_the_release_one_is_refused(self):
        with self.assertRaises(apk_release.Refused):
            apk_release.check_cert(NEW_FORMAT + f"V3 Signer: certificate SHA-256 digest: {DEBUG}\n")

    def test_no_certificate_is_refused(self):
        with self.assertRaises(apk_release.Refused):
            apk_release.check_cert("Verifies\n")

    def test_a_shortened_or_uppercase_digest_is_not_a_match(self):
        with self.assertRaises(apk_release.Refused):
            apk_release.check_cert(f"Signer #1 certificate SHA-256 digest: {CERT[:40]}\n")
        with self.assertRaises(apk_release.Refused):
            apk_release.check_cert(f"Signer #1 certificate SHA-256 digest: {CERT.upper()}\n")

    def test_an_apk_apksigner_rejects_is_refused_whatever_it_prints(self):
        with mock.patch.object(apk_release, "find_apksigner", return_value="apksigner"):
            with self.assertRaises(apk_release.Refused):
                apk_release.verify("x.apk", run=answer(NEW_FORMAT, returncode=1, stderr="DOES NOT VERIFY"))

    def test_the_readme_publishes_the_same_digest(self):
        readme = (apk_release.ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn(CERT, readme)


class ApksignerLookupTests(unittest.TestCase):
    def test_the_newest_build_tools_win(self):
        with tempfile.TemporaryDirectory() as sdk:
            for v in ("9.0.0", "35.0.0", "36.1.0"):
                d = pathlib.Path(sdk, "build-tools", v)
                d.mkdir(parents=True)
                (d / "apksigner").write_text("")
            with mock.patch.dict(os.environ, {"ANDROID_HOME": sdk}, clear=True):
                self.assertEqual(pathlib.Path(apk_release.find_apksigner()).parent.name, "36.1.0")

    def test_none_anywhere_is_refused(self):
        with mock.patch.dict(os.environ, {"PATH": ""}, clear=True):
            with self.assertRaises(apk_release.Refused):
                apk_release.find_apksigner()


class PrepareTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = pathlib.Path(self.tmp.name)
        self.apk = self.dir / "app-release.apk"
        with zipfile.ZipFile(self.apk, "w") as z:
            z.writestr("AndroidManifest.xml", "x")
            z.writestr("lib/arm64-v8a/libapp.so", "x")
            z.writestr("lib/x86_64/libapp.so", "x")
            z.writestr("lib/armeabi-v7a/libapp.so", "x")
        self.logs = self.dir / "changelogs"
        self.logs.mkdir()
        (self.logs / "33.txt").write_text("This version adds more than one wallet.\n", encoding="utf-8")
        patcher = mock.patch.object(apk_release, "find_apksigner", return_value="apksigner")
        patcher.start()
        self.addCleanup(patcher.stop)

    def prepare(self, run, build="33", version="2.6.0"):
        return apk_release.prepare(self.apk, version, build, self.dir / "out", changelogs=self.logs, run=run)

    def test_the_three_files(self):
        name, digest = self.prepare(answer(NEW_FORMAT))
        out = self.dir / "out"
        self.assertEqual(name, "soqushield-v2.6.0-build33.apk")
        self.assertEqual(sorted(p.name for p in out.iterdir()), ["SHA256SUMS", "notes.md", name])
        self.assertEqual((out / name).read_bytes(), self.apk.read_bytes())
        self.assertEqual(digest, hashlib.sha256(self.apk.read_bytes()).hexdigest())
        self.assertEqual((out / "SHA256SUMS").read_text(), f"{digest}  {name}\n")

    def test_the_release_text(self):
        name, digest = self.prepare(answer(NEW_FORMAT))
        text = (self.dir / "out" / "notes.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("This version adds more than one wallet.\n\n## Files\n"))
        self.assertIn(f"| `{name}` (arm64-v8a, armeabi-v7a, x86_64) | `{digest}` |", text)
        self.assertIn(f"`{CERT}`", text)
        self.assertNotIn("—", text)

    def test_a_wrong_signature_leaves_nothing_behind(self):
        with self.assertRaises(apk_release.Refused):
            self.prepare(answer(NEW_FORMAT.replace(CERT, DEBUG)))
        self.assertFalse((self.dir / "out").exists())

    def test_a_build_without_release_notes_is_refused(self):
        with self.assertRaises(apk_release.Refused):
            self.prepare(answer(NEW_FORMAT), build="34")
        (self.logs / "34.txt").write_text("  \n", encoding="utf-8")
        with self.assertRaises(apk_release.Refused):
            self.prepare(answer(NEW_FORMAT), build="34")

    def test_a_version_that_is_not_a_version_is_refused(self):
        for version, build in (("2.6", "33"), ("2.6.0", "33a"), ("../2.6.0", "33"), ("2.6.0", "")):
            with self.assertRaises(apk_release.Refused):
                self.prepare(answer(NEW_FORMAT), build=build, version=version)

    def test_the_command_reports_a_refusal_and_exits_1(self):
        with mock.patch.object(apk_release, "verify", side_effect=apk_release.Refused("no")):
            with mock.patch("sys.stderr"):
                self.assertEqual(apk_release.main(["verify", str(self.apk)]), 1)


if __name__ == "__main__":
    unittest.main()
