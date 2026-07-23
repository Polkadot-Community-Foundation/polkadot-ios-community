#!/usr/bin/env python3
"""Expire older TestFlight builds so only the latest N stay available to a beta group.

Scoped to a single external beta group (default "Products Devnet"): only builds
attached to that group are ever candidates, so Nightly / production builds that
share the same app record (io.pcf.polkadotapp) are never touched.

Dry-run unless APPLY=true. Expiry is irreversible (Apple has no un-expire).

Env:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_B64  App Store Connect API key (.p8 base64)
  BUNDLE_ID                                app bundle id (default io.pcf.polkadotapp)
  GROUP                                    beta group name (default "Products Devnet")
  KEEP                                     most-recent builds to keep active (default 1)
  APPLY                                    "true" to actually expire (else dry-run)
"""
import base64
import os
import sys
import time
from datetime import datetime, timezone

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"


def die(msg: str) -> None:
    print(f"::error::{msg}")
    sys.exit(1)


def token() -> str:
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    pem = base64.b64decode(os.environ["ASC_KEY_B64"]).decode()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        pem,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def get_all(session: requests.Session, url: str, params: dict | None = None) -> list:
    """Follow pagination, returning the concatenated `data` arrays."""
    out: list = []
    while url:
        r = session.get(url, params=params)
        params = None  # only first request carries params; links.next is fully-formed
        if r.status_code != 200:
            die(f"GET {url} -> {r.status_code}: {r.text[:400]}")
        body = r.json()
        out.extend(body.get("data", []))
        url = (body.get("links") or {}).get("next")
    return out


def fmt(dt: str) -> str:
    try:
        return datetime.fromisoformat(dt.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return dt or "?"


def main() -> None:
    bundle = os.environ.get("BUNDLE_ID", "io.pcf.polkadotapp")
    group_name = os.environ.get("GROUP", "Products Devnet")
    keep = max(1, int(os.environ.get("KEEP", "1") or "1"))
    apply = os.environ.get("APPLY", "").strip().lower() == "true"

    s = requests.Session()
    s.headers["Authorization"] = f"Bearer {token()}"

    apps = get_all(s, f"{API}/v1/apps", {"filter[bundleId]": bundle, "limit": 200})
    if not apps:
        die(f"No app found for bundle id {bundle}")
    app_id = apps[0]["id"]
    print(f"App: {bundle} (id {app_id})")

    groups = get_all(s, f"{API}/v1/apps/{app_id}/betaGroups", {"limit": 200})
    match = [g for g in groups if g["attributes"].get("name") == group_name]
    if not match:
        names = ", ".join(sorted(g["attributes"].get("name", "?") for g in groups))
        die(f'Beta group "{group_name}" not found. Available: {names}')
    group_id = match[0]["id"]
    print(f'Beta group: "{group_name}" (id {group_id})')

    builds = get_all(
        s,
        f"{API}/v1/builds",
        {
            "filter[app]": app_id,
            "filter[betaGroups]": group_id,
            "sort": "-uploadedDate",
            "limit": 200,
            "fields[builds]": "version,uploadedDate,expired,processingState",
        },
    )
    # newest first (sort=-uploadedDate); keep the first `keep` non-expired, expire the rest
    active = [b for b in builds if not b["attributes"].get("expired")]
    expired_already = [b for b in builds if b["attributes"].get("expired")]
    to_keep = active[:keep]
    to_expire = active[keep:]

    print(f"\nBuilds in group: {len(builds)} "
          f"({len(active)} active, {len(expired_already)} already expired)\n")
    print(f"{'build':>10}  {'uploaded':<17} {'state':<12} action")
    print("-" * 58)
    for b in active:
        a = b["attributes"]
        action = "KEEP" if b in to_keep else ("EXPIRE" if apply else "would-expire")
        print(f"{a.get('version','?'):>10}  {fmt(a.get('uploadedDate','')):<17} "
              f"{a.get('processingState','?'):<12} {action}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as fh:
            fh.write(f"### TestFlight prune — {group_name}\n\n")
            fh.write(f"Mode: {'APPLY (expiring)' if apply else 'dry-run'} · keep latest {keep}\n\n")
            fh.write("| build | uploaded | state | action |\n|--:|---|---|---|\n")
            for b in active:
                a = b["attributes"]
                action = "keep" if b in to_keep else ("**expired**" if apply else "would-expire")
                fh.write(f"| {a.get('version','?')} | {fmt(a.get('uploadedDate',''))} "
                         f"| {a.get('processingState','?')} | {action} |\n")

    if not to_expire:
        print("\nNothing to expire — only the latest build(s) are active.")
        return

    if not apply:
        print(f"\nDry-run: {len(to_expire)} build(s) WOULD be expired. "
              f"Re-run with apply=true to expire them.")
        return

    print(f"\nExpiring {len(to_expire)} build(s)...")
    for b in to_expire:
        bid = b["id"]
        r = s.patch(
            f"{API}/v1/builds/{bid}",
            json={"data": {"type": "builds", "id": bid, "attributes": {"expired": True}}},
        )
        ok = r.status_code in (200, 204)
        print(f"  build {b['attributes'].get('version','?')} (id {bid}): "
              f"{'expired' if ok else 'FAILED ' + str(r.status_code) + ' ' + r.text[:200]}")
        if not ok:
            die("Expire request failed; stopping.")
    print("Done.")


if __name__ == "__main__":
    main()
