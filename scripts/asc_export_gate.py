#!/usr/bin/env python3
"""The export-compliance gate for a processed TestFlight build (RELEASE_SUBMISSION_RUNBOOK.md, gate table).

    python3 scripts/asc_export_gate.py <build number> [--expect false|true] [--version 2.5.0]
                                       [--group "Soqucoin Beta" [--external]] [--whats-new TEXT]

Reads the build's export-compliance value (usesNonExemptEncryption) from App Store Connect. To Apple the value
means whether export documentation is due: false while the app is not distributed in France (standard
algorithms from a third-party library need documentation only on the French store), true once France is added
with a declaration record and Apple's code. When the value is unset the script sets the expected value, as the
plist key does at upload; a value once set cannot change. The build is attached to the App Store version, given
its What to Test text and added to the beta group only when the value reads the expected one and the beta state
is known and not MISSING_EXPORT_COMPLIANCE; otherwise the script exits 2 and attaches nothing. A beta group is
named and is the internal one unless --external is given; two groups of one name and kind refuse. Any write that
does not answer 2xx exits 1. Credentials come from ~/.soqushield-release.env through asc.py.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402

APP = "6759628525"


def ok(st):
    return 200 <= st < 300


def read_build(number):
    st, d = asc.req("GET", f"/v1/builds?filter[app]={APP}&filter[version]={number}"
                           "&fields[builds]=version,processingState,usesNonExemptEncryption"
                           "&include=buildBetaDetail&fields[buildBetaDetails]=internalBuildState,externalBuildState")
    rows = d.get("data", [])
    if not ok(st) or len(rows) != 1:
        return None, None, d
    states = [i["attributes"] for i in d.get("included", []) if i["type"] == "buildBetaDetails"]
    return rows[0], states, d


def main():
    p = argparse.ArgumentParser()
    p.add_argument("build", help="the build number as App Store Connect shows it, e.g. 32")
    p.add_argument("--expect", choices=["false", "true"], default="false",
                   help="the value the app's distribution needs: false while France is excluded")
    p.add_argument("--version", help="the App Store version string to attach the build to, e.g. 2.5.0")
    p.add_argument("--group", help="the name of the beta group to add the build to")
    p.add_argument("--external", action="store_true", help="the named group is the external one")
    p.add_argument("--whats-new", help="the What to Test text for en-US")
    a = p.parse_args()
    asc.load_env()
    expected = a.expect == "true"

    b, states, d = read_build(a.build)
    if b is None:
        print("build not found, or more than one build carries that number:", json.dumps(d)[:300]); return 1
    print("build", a.build, b["id"], b["attributes"], states)
    if b["attributes"].get("processingState") != "VALID":
        print("not processed yet"); return 1
    bid = b["id"]

    if b["attributes"].get("usesNonExemptEncryption") is None:
        st, d = asc.req("PATCH", f"/v1/builds/{bid}", {
            "data": {"type": "builds", "id": bid, "attributes": {"usesNonExemptEncryption": expected}}})
        print(f"set usesNonExemptEncryption {str(expected).lower()}:", st, json.dumps(d.get("errors"))[:200])
        b, states, d = read_build(a.build)
        if b is None:
            print("the read-back after the write failed:", json.dumps(d)[:300]); return 1
        print("read back", b["attributes"], states)

    value = b["attributes"].get("usesNonExemptEncryption")
    missing = (not states) or any(s.get("internalBuildState") == "MISSING_EXPORT_COMPLIANCE" for s in states)
    if value is not expected or missing:
        print(f"GATE: usesNonExemptEncryption reads {value!r} (expected {expected!r}); "
              f"beta state missing or unknown: {missing}. The build is not attached.")
        return 2
    print(f"gate passed: usesNonExemptEncryption reads {value!r}, beta states {states}")

    if a.whats_new:
        st, d = asc.req("GET", f"/v1/builds/{bid}/betaBuildLocalizations"
                               "?fields[betaBuildLocalizations]=locale,whatsNew")
        locs = [l for l in d.get("data", []) if l["attributes"].get("locale") == "en-US"]
        if locs:
            st, d = asc.req("PATCH", f"/v1/betaBuildLocalizations/{locs[0]['id']}",
                            {"data": {"id": locs[0]["id"], "type": "betaBuildLocalizations",
                                      "attributes": {"whatsNew": a.whats_new}}})
        else:
            st, d = asc.req("POST", "/v1/betaBuildLocalizations",
                            {"data": {"type": "betaBuildLocalizations",
                                      "attributes": {"locale": "en-US", "whatsNew": a.whats_new},
                                      "relationships": {"build": {"data": {"id": bid, "type": "builds"}}}}})
        print("what to test:", st, json.dumps(d.get("errors"))[:200])
        if not ok(st):
            return 1

    if a.version:
        st, d = asc.req("GET", f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS"
                               f"&filter[versionString]={a.version}&fields[appStoreVersions]=versionString,appStoreState")
        vs = d.get("data", [])
        if not ok(st) or len(vs) != 1:
            print("version not found once:", a.version, json.dumps(d)[:200]); return 1
        vid = vs[0]["id"]
        st, d = asc.req("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                        {"data": {"type": "builds", "id": bid}})
        print(f"attach to version {a.version}:", st, json.dumps(d.get("errors"))[:200])
        if not ok(st):
            return 1
        st, d = asc.req("GET", f"/v1/appStoreVersions/{vid}?fields[appStoreVersions]=versionString,appStoreState"
                               "&include=build&fields[builds]=version")
        print("version now:", d.get("data", {}).get("attributes"),
              "build", [i["attributes"] for i in d.get("included", [])])

    if a.group:
        st, d = asc.req("GET", f"/v1/betaGroups?filter[app]={APP}&fields[betaGroups]=name,isInternalGroup")
        gs = [g for g in d.get("data", []) if g["attributes"].get("name") == a.group
              and bool(g["attributes"].get("isInternalGroup")) == (not a.external)]
        if not ok(st) or len(gs) != 1:
            print(f"group not found once by name and kind: {a.group} ({'external' if a.external else 'internal'})")
            return 1
        st, d = asc.req("POST", f"/v1/betaGroups/{gs[0]['id']}/relationships/builds",
                        {"data": [{"id": bid, "type": "builds"}]})
        print(f"group {a.group}:", st, json.dumps(d)[:200])
        if not ok(st):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
