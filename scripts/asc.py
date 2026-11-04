#!/usr/bin/env python3
"""App Store Connect API helper for SoquShield TestFlight ops.

Stdlib-only (no fastlane needed for TestFlight ops). Credentials come from
~/.soqushield-release.env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
Recipe proven on the 2.1.0+16 external submission (2026-07-06); checked in
for +17 so it stops being session-ephemeral.

Usage:
  source ~/.soqushield-release.env   # or let the script read the file itself
  asc.py build <buildNumber>              # find the build id + state
  asc.py review-state <buildId>           # betaAppReviewSubmission state
  asc.py whatsnew <buildId> <text>        # set What to Test (en-US)
  asc.py beta-description <file>          # set the TestFlight Test Information description (en-US) from a file
  asc.py attach <buildId> <groupId>       # add build to a beta group
  asc.py submit <buildId>                 # submit for external beta review
  asc.py get <path>                       # raw GET, prints JSON

App: 6759628525 (org.soqu.soqushield). Known beta groups:
  f5c55e15-…  "Soqucoin Beta 2"   (external, 216 testers, join/a8tZaHU7)
  c8d5325a-…  "soqushield 2.1.0"  (external, join/jwYJAG9c)
Gotcha: builds/{id}/betaGroups is NOT a valid read endpoint — verify
membership from the group side (betaGroups/{id}/builds).
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.request

APP_ID = "6759628525"
API = "https://api.appstoreconnect.apple.com"


def load_env():
    path = os.path.expanduser("~/.soqushield-release.env")
    if os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.replace("export ", "").strip(), v.strip().strip('"'))


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def jwt() -> str:
    kid = os.environ["ASC_KEY_ID"]
    iss = os.environ["ASC_ISSUER_ID"]
    key_path = os.path.expanduser(os.environ["ASC_KEY_PATH"])
    header = b64url(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64url(json.dumps({"iss": iss, "iat": now, "exp": now + 1140,
                                 "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input, capture_output=True, check=True,
    ).stdout
    # DER ECDSA signature -> raw r||s (each 32 bytes) for JOSE
    def read_int(buf, off):
        assert buf[off] == 0x02
        ln = buf[off + 1]
        return buf[off + 2:off + 2 + ln], off + 2 + ln
    assert der[0] == 0x30
    r, off = read_int(der, 2)
    s, _ = read_int(der, off)
    raw = r.lstrip(b"\x00").rjust(32, b"\x00") + s.lstrip(b"\x00").rjust(32, b"\x00")
    return f"{header}.{payload}.{b64url(raw)}"


def req(method: str, path: str, body=None):
    r = urllib.request.Request(API + path, method=method,
                               headers={"Authorization": "Bearer " + jwt(),
                                        "Content-Type": "application/json"})
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(r, data=data) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def beta_description(path: str) -> int:
    """Set TestFlight's Test Information (en-US) from a file.

    The Test Information is shown on the TestFlight page for every build. It was set by hand until
    2026-10-21, when the 2.1.0 stagenet text was still live a week after the mainnet release; it is
    tracked in store-assets/TESTFLIGHT_BETA_DESCRIPTION.txt, which deliver's metadata does not carry.
    """
    with open(path, encoding="utf-8") as handle:
        text = handle.read().rstrip("\n")
    if not 1 <= len(text) <= 4000:
        print(f"refused: {len(text)} characters (App Store Connect allows 1 to 4000)")
        return 2
    st, d = req("GET", f"/v1/apps/{APP_ID}/betaAppLocalizations?fields[betaAppLocalizations]=locale,description")
    if st != 200:
        print(f"GET betaAppLocalizations failed: {st} {json.dumps(d)[:400]}")
        return 1
    locs = [l for l in d.get("data", []) if l["attributes"].get("locale") == "en-US"]
    if not locs:
        print("no en-US betaAppLocalization; create it in App Store Connect first")
        return 1
    st, d = req("PATCH", f"/v1/betaAppLocalizations/{locs[0]['id']}",
                {"data": {"id": locs[0]["id"], "type": "betaAppLocalizations",
                          "attributes": {"description": text}}})
    if st != 200:
        print(f"PATCH betaAppLocalizations failed: {st} {json.dumps(d)[:400]}")
        return 1
    live = d.get("data", {}).get("attributes", {}).get("description")
    if live != text:
        print(f"PATCH {st} but the description read back differs: {len(live or '')} characters live, "
              f"{len(text)} in the file")
        return 1
    print(f"{st} read back equal, {len(text)} characters")
    return 0


def main():
    load_env()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd == "build":
        version = sys.argv[2]
        st, d = req("GET", f"/v1/builds?filter[app]={APP_ID}&filter[version]={version}&fields[builds]=version,processingState,expired")
        print(json.dumps(d, indent=2))
    elif cmd == "review-state":
        build_id = sys.argv[2]
        st, d = req("GET", f"/v1/builds/{build_id}/betaAppReviewSubmission")
        print(json.dumps(d, indent=2))
    elif cmd == "whatsnew":
        build_id, text = sys.argv[2], sys.argv[3]
        # filter[locale] silently returns nothing on this nested endpoint
        # (caused a 409 duplicate-locale POST on the +20 release) — fetch all
        # and match client-side.
        st, d = req("GET", f"/v1/builds/{build_id}/betaBuildLocalizations?fields[betaBuildLocalizations]=locale,whatsNew")
        locs = [l for l in d.get("data", []) if l["attributes"].get("locale") == "en-US"]
        if locs:
            st, d = req("PATCH", f"/v1/betaBuildLocalizations/{locs[0]['id']}",
                        {"data": {"id": locs[0]["id"], "type": "betaBuildLocalizations",
                                  "attributes": {"whatsNew": text}}})
        else:
            st, d = req("POST", "/v1/betaBuildLocalizations",
                        {"data": {"type": "betaBuildLocalizations",
                                  "attributes": {"locale": "en-US", "whatsNew": text},
                                  "relationships": {"build": {"data": {"id": build_id, "type": "builds"}}}}})
        print(st, json.dumps(d, indent=2)[:400])
    elif cmd == "beta-description":
        sys.exit(beta_description(sys.argv[2]))
    elif cmd == "attach":
        build_id, group_id = sys.argv[2], sys.argv[3]
        st, d = req("POST", f"/v1/betaGroups/{group_id}/relationships/builds",
                    {"data": [{"id": build_id, "type": "builds"}]})
        print(st, json.dumps(d)[:400])
    elif cmd == "submit":
        build_id = sys.argv[2]
        st, d = req("POST", "/v1/betaAppReviewSubmissions",
                    {"data": {"type": "betaAppReviewSubmissions",
                              "relationships": {"build": {"data": {"id": build_id, "type": "builds"}}}}})
        print(st, json.dumps(d, indent=2)[:600])
    elif cmd == "get":
        st, d = req("GET", sys.argv[2])
        print(json.dumps(d, indent=2))
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
