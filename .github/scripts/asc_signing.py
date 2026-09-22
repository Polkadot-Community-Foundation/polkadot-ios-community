#!/usr/bin/env python3
"""App Store Connect helpers for the signing jobs.

  preflight            key accepted? app record visible? TestFlight group present and internal?
  revoke-runner-certs  revoke the signing certificates THIS runner created, so CI never
                       accumulates certificates in the team account.

Why revoke: a fresh macOS runner has an empty keychain, so automatic signing with
-allowProvisioningUpdates asks Apple for a new Apple Development certificate on every run.
Nothing removed them, and the team hit Apple's certificate limit.

A certificate is revoked only if BOTH hold:
  - its serial number is in this runner's keychain (Xcode created or imported it here), and
  - it was created during this run (Apple certificates expire exactly one year after
    creation, so its expiry is within a day of SIGN_STARTED + 365 days).
Anyone's local certificate fails the first test; a persistent certificate imported from a
secret fails the second.

Env:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_B64  App Store Connect API key (.p8 base64)
  BUNDLE_ID          preflight: app bundle id (default io.pcf.polkadotapp)
  TESTFLIGHT_GROUP   preflight: group the build is for (optional)
  SIGN_STARTED       revoke-runner-certs: unix time the job started
"""
import base64
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

import jwt
import requests
from cryptography import x509

API = "https://api.appstoreconnect.apple.com"


def die(msg: str) -> None:
    print(f"::error::{msg}")
    sys.exit(1)


def session() -> requests.Session:
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        base64.b64decode(os.environ["ASC_KEY_B64"]).decode(),
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )
    s = requests.Session()
    s.headers["Authorization"] = f"Bearer {token}"
    return s


def get_all(s: requests.Session, url: str, params: dict | None = None) -> list:
    out: list = []
    while url:
        r = s.get(url, params=params)
        params = None
        if r.status_code != 200:
            die(f"GET {url} -> {r.status_code}: {r.text[:400]}")
        body = r.json()
        out.extend(body.get("data", []))
        url = (body.get("links") or {}).get("next")
    return out


def preflight() -> None:
    key_id, issuer = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]
    print(f"key id {key_id[:4]}…  issuer {issuer[:8]}…")
    s = session()
    bundle = os.environ.get("BUNDLE_ID") or "io.pcf.polkadotapp"
    apps = get_all(s, f"{API}/v1/apps", {"filter[bundleId]": bundle, "limit": 200})
    if not apps:
        die(f"key accepted, but no app record for {bundle} is visible to it")
    app_id = apps[0]["id"]
    print(f"key accepted; app record {bundle} = {app_id}")

    groups = get_all(s, f"{API}/v1/apps/{app_id}/betaGroups", {"limit": 200})
    for g in groups:
        a = g["attributes"]
        print(f"  group {a['name']!r}: internal={a.get('isInternalGroup')} all_builds={a.get('hasAccessToAllBuilds')}")
    want = os.environ.get("TESTFLIGHT_GROUP")
    if not want:
        return
    match = [g["attributes"] for g in groups if g["attributes"]["name"] == want]
    if not match:
        die(f"TestFlight group {want!r} not found on {bundle}")
    if not match[0].get("isInternalGroup"):
        die(f"{want!r} is an EXTERNAL group; this lane distributes to internal groups only")
    if match[0].get("hasAccessToAllBuilds"):
        print(f"::warning::{want!r} receives ALL builds automatically, other lanes' builds included")


def runner_serials() -> set[int]:
    pem = subprocess.run(["security", "find-certificate", "-a", "-p"],
                         capture_output=True, text=True).stdout
    serials = set()
    for block in pem.split("-----END CERTIFICATE-----"):
        if "-----BEGIN CERTIFICATE-----" not in block:
            continue
        try:
            cert = x509.load_pem_x509_certificate((block + "-----END CERTIFICATE-----").encode())
        except ValueError:
            continue
        serials.add(cert.serial_number)
    return serials


def revoke_runner_certs() -> None:
    started = datetime.fromtimestamp(int(os.environ["SIGN_STARTED"]), timezone.utc)
    earliest, latest = started + timedelta(days=364), datetime.now(timezone.utc) + timedelta(days=366)
    local = runner_serials()
    s = session()
    revoked = 0
    for c in get_all(s, f"{API}/v1/certificates", {"limit": 200}):
        a = c["attributes"]
        try:
            serial = int(a.get("serialNumber") or "", 16)
            expires = datetime.fromisoformat(a["expirationDate"].replace("Z", "+00:00"))
        except (ValueError, KeyError, AttributeError):
            continue
        if serial not in local or not (earliest <= expires <= latest):
            continue
        r = s.delete(f"{API}/v1/certificates/{c['id']}")
        if r.status_code not in (204, 404):
            die(f"revoking {a.get('certificateType')} {a.get('name')!r} ({c['id']}) -> {r.status_code}: {r.text[:300]}")
        print(f"revoked {a.get('certificateType')} {a.get('name')!r} ({c['id']}), created this run")
        revoked += 1
    print(f"revoked {revoked} certificate(s) created by this runner")


if __name__ == "__main__":
    commands = {"preflight": preflight, "revoke-runner-certs": revoke_runner_certs}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        die(f"usage: asc_signing.py {{{'|'.join(commands)}}}")
    commands[sys.argv[1]]()
