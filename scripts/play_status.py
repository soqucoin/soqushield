#!/usr/bin/env python3
"""Read-only Google Play track status for SoquShield.

Stdlib-only sibling of asc.py: signs the service-account JWT with openssl,
exchanges it for an access token, opens a throwaway edit, reads every track,
then deletes the edit. Credentials: PLAY_JSON_KEY_PATH in
~/.soqushield-release.env.

Usage: play_status.py            every track and its releases
       play_status.py --max-code  the highest version code on any track, as one integer (0 with none);
                                  the release workflow skips an upload whose build number is not above it
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

PACKAGE = "org.soqu.soqushield"
API = "https://androidpublisher.googleapis.com/androidpublisher/v3"


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


def token() -> str:
    key = json.load(open(os.path.expanduser(os.environ["PLAY_JSON_KEY_PATH"])))
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    now = int(time.time())
    claims = b64url(json.dumps({
        "iss": key["client_email"],
        "scope": "https://www.googleapis.com/auth/androidpublisher",
        "aud": "https://oauth2.googleapis.com/token",
        "iat": now, "exp": now + 1800,
    }).encode())
    signing_input = f"{header}.{claims}".encode()
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as f:
        f.write(key["private_key"])
        pem = f.name
    try:
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", pem],
                             input=signing_input, capture_output=True, check=True).stdout
    finally:
        os.unlink(pem)
    assertion = f"{header}.{claims}.{b64url(sig)}"
    body = ("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"
            f"&assertion={assertion}").encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    return json.load(urllib.request.urlopen(req))["access_token"]


# Answers worth a second try: Google's own overload and rate limits. A 503 came back once to the
# delete of a read-only edit while ten release runs read the store at once, and failed a run that
# had nothing to upload. Three more attempts, 2, 4 and 8 seconds apart; the last one raises.
RETRY_STATUSES = {429, 500, 502, 503, 504}
ATTEMPTS = 4


def call(tok, method, path, body=None):
    req = urllib.request.Request(f"{API}{path}", method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {tok}",
                                          "Content-Type": "application/json"})
    for attempt in range(1, ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(req) as r:
                data = r.read()
                return json.loads(data) if data else {}
        except urllib.error.HTTPError as e:
            if e.code not in RETRY_STATUSES or attempt == ATTEMPTS:
                raise
            print(f"play_status: {method} {path} answered {e.code}; attempt {attempt} of {ATTEMPTS}, "
                  f"waiting {2 ** attempt} s", file=sys.stderr)
            time.sleep(2 ** attempt)


def max_version_code(tracks):
    """The highest version code in any release on any track of a tracks listing, 0 with none."""
    codes = [int(c) for t in tracks.get("tracks", []) for rel in t.get("releases", [])
             for c in (rel.get("versionCodes") or [])]
    return max(codes) if codes else 0


def main():
    load_env()
    tok = token()
    edit = call(tok, "POST", f"/applications/{PACKAGE}/edits", {})
    edit_id = edit["id"]
    try:
        tracks = call(tok, "GET", f"/applications/{PACKAGE}/edits/{edit_id}/tracks")
        if "--max-code" in sys.argv[1:]:
            print(max_version_code(tracks))
            return
        for t in tracks.get("tracks", []):
            print(f"track: {t['track']}")
            for rel in t.get("releases", []):
                print(f"  status={rel.get('status')} name={rel.get('name')} "
                      f"versionCodes={rel.get('versionCodes')} "
                      f"rollout={rel.get('userFraction', 'full')}")
    finally:
        # Best effort: the edit carries no change, and nobody commits it. A delete that fails
        # must not turn a successful read into a failed step.
        try:
            call(tok, "DELETE", f"/applications/{PACKAGE}/edits/{edit_id}")
        except Exception as e:  # noqa: BLE001
            print(f"play_status: the read-only edit {edit_id} was not deleted ({e}); "
                  "it carries no change", file=sys.stderr)


if __name__ == "__main__":
    main()
