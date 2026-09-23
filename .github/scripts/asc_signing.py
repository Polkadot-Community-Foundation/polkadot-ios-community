#!/usr/bin/env python3
"""App Store Connect helpers for the signing jobs.

  load-signing-material  production: fetch the App Store Connect key from Secret Manager,
                         write it to $RUNNER_TEMP/asc (0600) and export its ids to $GITHUB_ENV.
  preflight              key accepted? app record visible? TestFlight group present and internal?
  revoke-runner-certs    revoke the signing certificates THIS runner created, so CI never
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
  ASC_KEY_ID, ASC_ISSUER_ID  App Store Connect API key id and issuer id
  ASC_KEY_PATH | ASC_KEY_B64 the .p8 key: a file (production) or its base64 (devnet)
  BUNDLE_ID          preflight: app bundle id (default io.pcf.polkadotapp)
  TESTFLIGHT_GROUP   preflight: group the build is for (optional)
  SIGN_STARTED       revoke-runner-certs: unix time the job started
  IOS_SIGNING_SECRET load-signing-material: projects/<p>/secrets/<s>, a YAML map with
                     key-id, issuer-id, team-id, private-key
  GCP_ACCESS_TOKEN   load-signing-material: token of the identity allowed to read it
"""
import base64
import binascii
import os
import plistlib
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from typing import NoReturn

import jwt
import requests
import yaml
from cryptography import x509
from cryptography.exceptions import UnsupportedAlgorithm
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

API = "https://api.appstoreconnect.apple.com"
SECRET_MANAGER = "https://secretmanager.googleapis.com/v1"
HTTP_TIMEOUT = 30  # seconds; no call may hang the always() revoke step
SECRET_NAME = re.compile(r"projects/[a-z0-9-]+/secrets/[A-Za-z0-9_-]+")
IDS = {
    "key-id": re.compile(r"[A-Z0-9]{10}"),
    "issuer-id": re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"),
    "team-id": re.compile(r"[A-Z0-9]{10}"),
}
SIGNING_KEYS = {*IDS, "private-key"}
# Distribution material: all four together or none. Without them the lane cannot sign.
DISTRIBUTION_KEYS = {"distribution-p12", "distribution-p12-password", "profile-app", "profile-extension"}


def die(msg: str) -> NoReturn:
    print(f"::error::{msg}")
    sys.exit(1)


def _crc32c_table() -> tuple[int, ...]:
    table = []
    for n in range(256):
        c = n
        for _ in range(8):
            c = (c >> 1) ^ 0x82F63B78 if c & 1 else c >> 1
        table.append(c)
    return tuple(table)


CRC32C_TABLE = _crc32c_table()


def crc32c(data: bytes) -> int:
    """CRC-32C (Castagnoli), the checksum Secret Manager returns as dataCrc32c."""
    crc = 0xFFFFFFFF
    for b in data:
        crc = CRC32C_TABLE[(crc ^ b) & 0xFF] ^ (crc >> 8)
    return crc ^ 0xFFFFFFFF


def private_key_pem() -> str:
    path = os.environ.get("ASC_KEY_PATH")
    if path:
        with open(path, encoding="ascii") as f:
            return f.read()
    return base64.b64decode(os.environ["ASC_KEY_B64"]).decode()


def session() -> requests.Session:
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        private_key_pem(),
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )
    s = requests.Session()
    s.headers["Authorization"] = f"Bearer {token}"
    return s


def get_all(s: requests.Session, url: str, params: dict | None = None) -> list:
    out: list = []
    while url:
        try:
            r = s.get(url, params=params, timeout=HTTP_TIMEOUT)
        except requests.RequestException as e:
            die(f"GET {url} failed: {type(e).__name__}")
        params = None
        if r.status_code != 200:
            die(f"GET {url} -> {r.status_code}: {r.text[:400]}")
        try:
            body = r.json()
        except ValueError:
            die(f"GET {url} -> 200 with a non-JSON body")
        out.extend(body.get("data", []))
        url = (body.get("links") or {}).get("next")
    return out


def access_secret(name: str, token: str) -> tuple[str, bytes]:
    """Latest version of a Secret Manager secret: (version name, payload bytes)."""
    url = f"{SECRET_MANAGER}/{name}/versions/latest:access"
    try:
        r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=HTTP_TIMEOUT)
    except requests.RequestException as e:
        die(f"GET {url} failed: {type(e).__name__}")
    if r.status_code != 200:
        die(f"GET {url} -> {r.status_code}: {r.text[:400]}")
    # From here on the body carries the secret: never echo it.
    try:
        body = r.json()
        payload = body["payload"]
        data = base64.b64decode(payload["data"], validate=True)
        want = payload.get("dataCrc32c")
        want = None if want is None else int(want)
    except (ValueError, KeyError, TypeError, binascii.Error):
        die(f"{name}: unexpected Secret Manager response shape")
    if want is not None and crc32c(data) != want:
        die(f"{name}: payload CRC32C mismatch; refusing a corrupted secret")
    return str(body.get("name", name)), data


def parse_signing_material(raw: bytes) -> dict[str, str]:
    try:
        material = yaml.safe_load(raw.decode("utf-8"))
    except (UnicodeDecodeError, yaml.YAMLError):
        die("signing material is not valid UTF-8 YAML")
    if not isinstance(material, dict):
        die("signing material is not a YAML map")
    extra = set(material) - SIGNING_KEYS
    if set(material) & SIGNING_KEYS != SIGNING_KEYS or extra - DISTRIBUTION_KEYS:
        keys = ", ".join(sorted(map(str, material)))
        die(f"signing material keys are [{keys}]; expected [{', '.join(sorted(SIGNING_KEYS))}]"
            f" plus optionally [{', '.join(sorted(DISTRIBUTION_KEYS))}]")
    if extra and extra != DISTRIBUTION_KEYS:
        die(f"distribution material is incomplete: missing [{', '.join(sorted(DISTRIBUTION_KEYS - extra))}]")
    if not all(isinstance(v, str) for v in material.values()):
        die("every signing material value must be a string")

    # Mask before anything else can print them; line by line, so a stray newline cannot unmask.
    for k in (*IDS, "private-key", *(DISTRIBUTION_KEYS & set(material))):
        for line in material[k].splitlines():
            line = line.strip()
            if line and not line.startswith("-----"):
                print(f"::add-mask::{line}")

    for k in sorted(set(material) & DISTRIBUTION_KEYS):
        try:
            base64.b64decode(material[k], validate=True) if k != "distribution-p12-password" else None
        except binascii.Error:
            die(f"{k} is not base64")
    for k, pattern in IDS.items():
        if not pattern.fullmatch(material[k]):
            die(f"{k} is malformed")
    pem = material["private-key"].strip() + "\n"
    if not pem.startswith("-----BEGIN PRIVATE KEY-----"):
        die("private-key is not a PKCS#8 PEM (-----BEGIN PRIVATE KEY-----)")
    try:
        key = serialization.load_pem_private_key(pem.encode("ascii"), password=None)
    except (ValueError, TypeError, UnicodeEncodeError, UnsupportedAlgorithm):
        die("private-key does not load as an unencrypted private key")
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
        die("private-key is not an EC P-256 key")
    return {**material, "private-key": pem}


def write_private(directory: str, name: str, content: bytes) -> str:
    """Write 0600, refusing to follow a symlink, and return the path."""
    path = os.path.join(directory, name)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as f:
        os.fchmod(f.fileno(), 0o600)
        f.write(content)
    return path


def profile_identity(field: str, raw: bytes) -> tuple[str, str]:
    """(Name, UUID) of a .mobileprovision, and reject anything but an App Store profile."""
    start, end = raw.find(b"<?xml"), raw.find(b"</plist>")
    if start < 0 or end < 0:
        die(f"{field}: no plist payload in the provisioning profile")
    try:
        profile = plistlib.loads(raw[start:end + len(b"</plist>")])
    except (plistlib.InvalidFileException, ValueError):
        die(f"{field}: the provisioning profile payload does not parse")
    if "ProvisionedDevices" in profile:
        die(f"{field}: has a device list, so it is not an App Store profile")
    name, uuid = profile.get("Name"), profile.get("UUID")
    if not isinstance(name, str) or not isinstance(uuid, str):
        die(f"{field}: the provisioning profile has no Name/UUID")
    return name, uuid


def load_signing_material() -> None:
    name = os.environ.get("IOS_SIGNING_SECRET", "")
    if not SECRET_NAME.fullmatch(name):
        die("IOS_SIGNING_SECRET must be projects/<project>/secrets/<secret>")
    token = os.environ.get("GCP_ACCESS_TOKEN") or die("GCP_ACCESS_TOKEN is empty")
    version, raw = access_secret(name, token)
    material = parse_signing_material(raw)

    key_dir = os.path.join(os.environ["RUNNER_TEMP"], "asc")
    os.makedirs(key_dir, mode=0o700, exist_ok=True)
    os.chmod(key_dir, 0o700)
    key_path = write_private(key_dir, f"AuthKey_{material['key-id']}.p8", material["private-key"].encode("ascii"))

    exports = {
        "ASC_KEY_ID": material["key-id"],
        "ASC_ISSUER_ID": material["issuer-id"],
        "TEAM_ID": material["team-id"],
        "ASC_KEY_PATH": key_path,
    }

    # Distribution material, when present: the lane signs manually from it, so xcodebuild never asks Apple's
    # portal for a certificate or a profile. Profiles go where Xcode looks for them as well as beside the key.
    if DISTRIBUTION_KEYS <= set(material):
        exports["P12_PATH"] = write_private(key_dir, "distribution.p12",
                                            base64.b64decode(material["distribution-p12"]))
        exports["P12_PASSWORD"] = material["distribution-p12-password"]
        installed = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
        os.makedirs(installed, exist_ok=True)
        for field, var in (("profile-app", "PROFILE_APP"), ("profile-extension", "PROFILE_EXTENSION")):
            raw_profile = base64.b64decode(material[field])
            name, uuid = profile_identity(field, raw_profile)
            write_private(key_dir, f"{uuid}.mobileprovision", raw_profile)
            write_private(installed, f"{uuid}.mobileprovision", raw_profile)
            exports[f"{var}_NAME"] = name
            print(f"installed profile {name!r} ({uuid})")

    print(f"signing material loaded from {version}")


def preflight() -> None:
    s = session()
    bundle = os.environ.get("BUNDLE_ID") or "io.pcf.polkadotapp"
    # filter[bundleId] also returns apps whose bundle id merely contains it: match exactly.
    found = get_all(s, f"{API}/v1/apps", {"filter[bundleId]": bundle, "limit": 200})
    apps = [a for a in found if a["attributes"].get("bundleId") == bundle]
    if len(apps) != 1:
        seen = ", ".join(sorted(str(a["attributes"].get("bundleId")) for a in found)) or "none"
        die(f"key accepted, but {len(apps)} app records match {bundle} exactly (returned: {seen})")
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
        try:
            r = s.delete(f"{API}/v1/certificates/{c['id']}", timeout=HTTP_TIMEOUT)
        except requests.RequestException as e:
            die(f"revoking {a.get('certificateType')} {a.get('name')!r} ({c['id']}) failed: {type(e).__name__}")
        if r.status_code not in (204, 404):
            die(f"revoking {a.get('certificateType')} {a.get('name')!r} ({c['id']}) -> {r.status_code}: {r.text[:300]}")
        print(f"revoked {a.get('certificateType')} {a.get('name')!r} ({c['id']}), created this run")
        revoked += 1
    print(f"revoked {revoked} certificate(s) created by this runner")


if __name__ == "__main__":
    commands = {
        "load-signing-material": load_signing_material,
        "preflight": preflight,
        "revoke-runner-certs": revoke_runner_certs,
    }
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        die(f"usage: asc_signing.py {{{'|'.join(commands)}}}")
    commands[sys.argv[1]]()
