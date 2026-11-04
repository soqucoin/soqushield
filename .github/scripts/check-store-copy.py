#!/usr/bin/env python3
"""Refuse the pre-launch wording in the public copy of the app.

Mainnet has run since 13 October 2026. The listing text, the TestFlight description, the current
changelog and the README describe the app as it is. The phrases below belong to the builds before the
launch, and one of them reached a live store page for a month (the Play short description read
"Stagenet beta.").

Scanned: every .txt under android/fastlane/metadata and ios/fastlane/metadata (of the Android
changelogs only default.txt and the file of the build pubspec.yaml names, because older changelogs are
a record), store-assets/*.txt and README.md. Exit 1 with every hit listed, 0 with none.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

PHRASES = [
    "stagenet beta",
    "mainnet has not launched",
    "open at mainnet launch",
    "at mainnet launch",
    "until mainnet launch",
    "before mainnet launch",
    "no real value",
    "no monetary value",
    "test coins with no",
    "hosted beta",
    "current release: stagenet",
    "usdsoq",
    "faucet",
    "lightning",
    "pay over",
]


def current_build():
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    m = re.search(r"^version:\s*[\d.]+\+(\d+)", text, re.M)
    return m.group(1) if m else None


def files():
    build = current_build()
    for base in ("android/fastlane/metadata", "ios/fastlane/metadata"):
        for p in sorted((ROOT / base).rglob("*.txt")):
            if p.parent.name == "changelogs" and p.name not in ("default.txt", f"{build}.txt"):
                continue
            yield p
    yield from sorted((ROOT / "store-assets").glob("*.txt"))
    yield ROOT / "README.md"


def main():
    hits = []
    for p in files():
        for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            low = line.lower()
            for phrase in PHRASES:
                if phrase in low:
                    hits.append(f"{p.relative_to(ROOT)}:{n}: {phrase!r}")
    for h in hits:
        print(h)
    if hits:
        print(f"{len(hits)} pre-launch phrase(s); rewrite the text for the live network")
        return 1
    print("store copy: no pre-launch wording")
    return 0


if __name__ == "__main__":
    sys.exit(main())
