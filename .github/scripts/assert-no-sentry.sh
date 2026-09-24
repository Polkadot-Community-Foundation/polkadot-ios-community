#!/usr/bin/env bash
# Fails when Sentry is present in a built .app: the production lane excludes sentry-cocoa from the
# package graph (EXCLUDED_PACKAGES), and Release calls no Sentry API, so a disabled analytics SDK
# and its privacy manifest must not ship. Catches an upstream sync quietly reintroducing it.
#
#   assert-no-sentry.sh <path to .app>
set -euo pipefail

app=${1:?usage: assert-no-sentry.sh <path to .app>}
[ -d "$app" ] || { echo "::error::$app is not a bundle"; exit 1; }

fail=0

# 1. Nothing named after it: the framework, its PrivacyInfo, any resource bundle.
while IFS= read -r path; do
  echo "::error::Sentry is bundled: ${path#"$app/"}"
  fail=1
done < <(find "$app" -iname "*sentry*")

# 2. No code from it, in the app or anything it embeds. Linked Sentry leaves its class and
#    type names in the binary even when no call site survives compilation.
while IFS= read -r binary; do
  file "$binary" | grep -q "Mach-O" || continue
  hits=$(strings -a "$binary" | grep -cE "SentrySDK|SentryCrash|sentry-cocoa" || true)
  if [ "$hits" -gt 0 ]; then
    echo "::error::${binary#"$app/"} carries Sentry symbols ($hits references)"
    fail=1
  fi
done < <(find "$app" -type f -perm -u+x)

if [ "$fail" -ne 0 ]; then
  echo "::error::Sentry must not reach a production build; see EXCLUDED_PACKAGES in the workflow"
  exit 1
fi
echo "no Sentry in $(basename "$app"): not bundled, no symbols in any executable"
