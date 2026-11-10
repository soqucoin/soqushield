#!/usr/bin/env python3
"""The APK on the GitHub Releases page: the signing check and the release files.

Every APK on that page is signed with one key, so a release installs over the previous one. The
release workflow builds the APK from a tagged commit and publishes nothing until this script has
read the certificate out of the built file and found the one below, and no other.

Stdlib only. The certificate is read with apksigner from the Android SDK's build-tools (the newest
under ANDROID_HOME or ANDROID_SDK_ROOT, else the one on PATH).

Usage: apk_release.py verify <apk>
           exit 0 when the APK's signatures verify and its only signing certificate is the release one
       apk_release.py prepare <apk> --version 2.6.0 --build 33 --out <dir>
           the same check, then <dir> receives the three things a release carries:
           soqushield-v<version>-build<build>.apk, SHA256SUMS and notes.md (the release text: the
           Play changelog of that build, the file's SHA-256 and the certificate's digest)
"""
import argparse
import hashlib
import os
import pathlib
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

# SHA-256 of the certificate that signed every APK on the Releases page since 2.0.0. README.md
# publishes the same digest; test_apk_release.py holds the two together.
SIGNING_CERT_SHA256 = "f274e1a60220ff095f9a4451cd0ac956450e9a0e3b619d44c1da10058830ede5"

CHANGELOGS = ROOT / "android/fastlane/metadata/android/en-US/changelogs"


class Refused(Exception):
    """The APK, or the tree, is not in a state a release can be made from."""


def find_apksigner():
    found = []
    for var in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        base = os.environ.get(var)
        if base:
            found += pathlib.Path(base, "build-tools").glob("*/apksigner")
    if found:
        def version(p):
            return [int(n) for n in re.findall(r"\d+", p.parent.name)]
        return str(max(found, key=version))
    on_path = shutil.which("apksigner")
    if on_path:
        return on_path
    raise Refused("apksigner not found: set ANDROID_HOME to an SDK with build-tools, or put apksigner on PATH")


def cert_digests(printed):
    """Every certificate SHA-256 digest in `apksigner verify --print-certs` output. The line reads
    `Signer #1 certificate SHA-256 digest: <hex>` or `V2 Signer: certificate SHA-256 digest: <hex>`,
    by the build-tools version."""
    return set(re.findall(r"certificate SHA-256 digest: ([0-9a-f]{64})\b", printed))


def check_cert(printed, expected=SIGNING_CERT_SHA256):
    """Refuse unless the output names the release certificate and no other certificate."""
    digests = cert_digests(printed)
    if not digests:
        raise Refused("apksigner printed no signing certificate")
    if digests != {expected}:
        raise Refused(
            "the APK is not signed with the release key alone. Certificates found: "
            + ", ".join(sorted(digests)) + ". Expected: " + expected
            + ". An APK with another signature does not install over a published one.")


def verify(apk, run=subprocess.run):
    """Check the APK's signatures and its certificate; return apksigner's output."""
    done = run([find_apksigner(), "verify", "--print-certs", str(apk)], capture_output=True, text=True)
    if done.returncode != 0:
        raise Refused("apksigner does not verify the APK:\n" + (done.stdout + done.stderr).strip())
    check_cert(done.stdout)
    return done.stdout


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def abis(apk):
    """The ABIs the APK carries native code for, read from its lib/<abi>/ entries."""
    with zipfile.ZipFile(apk) as z:
        return sorted({n.split("/")[1] for n in z.namelist() if n.startswith("lib/") and n.count("/") >= 2})


def changelog(build, base=None):
    path = pathlib.Path(base or CHANGELOGS) / f"{build}.txt"
    text = path.read_text(encoding="utf-8").strip() if path.exists() else ""
    if not text:
        raise Refused(f"the release notes for build {build} are not written: {path} is missing or empty")
    return text


def notes(name, digest, abi_list, text):
    carried = f" ({', '.join(abi_list)})" if abi_list else ""
    return (
        f"{text}\n\n"
        "## Files\n\n"
        "| File | SHA-256 |\n"
        "|---|---|\n"
        f"| `{name}`{carried} | `{digest}` |\n\n"
        "The APK is signed with the same key as every previous release, so it installs over an "
        "existing SoquShield. The signing certificate's SHA-256 digest is "
        f"`{SIGNING_CERT_SHA256}`; `apksigner verify --print-certs` shows it.\n"
    )


def prepare(apk, version, build, out, changelogs=None, run=subprocess.run):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"\d+", build):
        raise Refused(f"not a version and a build number: {version!r} {build!r}")
    text = changelog(build, changelogs)
    verify(apk, run=run)
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    name = f"soqushield-v{version}-build{build}.apk"
    shutil.copyfile(apk, out / name)
    digest = sha256(out / name)
    (out / "SHA256SUMS").write_text(f"{digest}  {name}\n", encoding="utf-8")
    (out / "notes.md").write_text(notes(name, digest, abis(out / name), text), encoding="utf-8")
    return name, digest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    v = sub.add_parser("verify")
    v.add_argument("apk")
    p = sub.add_parser("prepare")
    p.add_argument("apk")
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "verify":
            verify(args.apk)
            print(f"signed with the release certificate {SIGNING_CERT_SHA256}")
            print(f"sha256 {sha256(args.apk)}")
        else:
            name, digest = prepare(args.apk, args.version, args.build, args.out)
            print(f"{digest}  {name}")
    except Refused as e:
        print(f"refused: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
