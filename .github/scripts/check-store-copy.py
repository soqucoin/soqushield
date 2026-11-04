#!/usr/bin/env python3
"""Refuse the pre-launch wording in the public copy of the app.

Mainnet has run since 13 October 2026. The listing text, the TestFlight description, the current
changelog and the README describe the app as it is. The phrases below belong to the builds before the
launch, and one of them reached a live store page for a month (the Play short description read
"Stagenet beta.").

Scanned: every .txt under android/fastlane/metadata and ios/fastlane/metadata (of the Android
changelogs only default.txt and the file of the build pubspec.yaml names, because older changelogs are
a record), store-assets/*.txt and README.md. A phrase is found across any run of whitespace, so a line
wrap does not hide it, and each hit names the line it starts on. Exit 1 with every hit listed, 0 with
none. `--selftest` runs the matcher over fixed samples and exits 0 when every case holds.
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


def find(text, phrases=PHRASES):
    """Every phrase in text, with the 1-based line its match starts on; whitespace of any kind and
    any length may sit between the words of a phrase, and a phrase matches whole words only."""
    low = text.lower()
    hits = []
    for phrase in phrases:
        pattern = r"\b" + r"\s+".join(re.escape(word) for word in phrase.split()) + r"\b"
        for m in re.finditer(pattern, low):
            hits.append((low.count("\n", 0, m.start()) + 1, phrase))
    return sorted(set(hits))


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


def selftest():
    cases = [
        ("Mainnet has\nnot launched.", [(1, "mainnet has not launched")]),
        ("Balances open at\n    mainnet launch.", [(1, "at mainnet launch"), (1, "open at mainnet launch")]),
        ("ok\nok\nno real value here", [(3, "no real value")]),
        ("STAGENET BETA", [(1, "stagenet beta")]),
        ("Soqucoin mainnet launched on 13 October 2026.", []),
        ("Stagenet, the public test network, is one tap away.", []),
        ("A wallet that mainnet launches nothing.", []),
    ]
    failed = 0
    for text, expected in cases:
        got = find(text)
        if got != sorted(expected):
            failed += 1
            print(f"selftest: {text!r}: expected {sorted(expected)}, got {got}")
    print(f"selftest: {len(cases) - failed} of {len(cases)} cases hold")
    return 1 if failed else 0


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    hits = []
    for p in files():
        for line, phrase in find(p.read_text(encoding="utf-8")):
            hits.append(f"{p.relative_to(ROOT)}:{line}: {phrase!r}")
    for h in hits:
        print(h)
    if hits:
        print(f"{len(hits)} pre-launch phrase(s); rewrite the text for the live network")
        return 1
    print("store copy: no pre-launch wording")
    return 0


if __name__ == "__main__":
    sys.exit(main())
