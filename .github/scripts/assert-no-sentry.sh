#!/usr/bin/env bash
# Fails when Sentry is present in a built .app. The production lane excludes sentry-cocoa from the
# package graph; this proves it on the product, so a sync cannot quietly bring it back.
#
#   assert-no-sentry.sh <path to .app>
set -euo pipefail

app=${1:?usage: assert-no-sentry.sh <path to .app>}
[ -d "$app" ] || { echo "::error::$app is not a bundle"; exit 1; }
# Without it the symbol scan would read nothing and report success.
command -v strings >/dev/null || { echo "::error::strings is not available"; exit 1; }

fail=0

# 1. Nothing named after it: the framework, its PrivacyInfo, any resource bundle.
while IFS= read -r path; do
  echo "::error::Sentry is bundled: ${path#"$app/"}"
  fail=1
done < <(find "$app" -iname "*sentry*")

# 2. No code from it: linked Sentry leaves its type names in the binary with no call site.
scanned=0
while IFS= read -r binary; do
  file "$binary" | grep -q "Mach-O" || continue
  scanned=$((scanned + 1))
  hits=$(strings -a "$binary" | grep -cE "SentrySDK|SentryCrash|sentry-cocoa" || true)
  if [ "$hits" -gt 0 ]; then
    echo "::error::${binary#"$app/"} carries Sentry symbols ($hits references)"
    fail=1
  fi
done < <(find "$app" -type f)   # not -perm -u+x: the exec bit need not survive export

# An empty or wrong bundle must not pass for having been read.
[ "$scanned" -gt 0 ] || { echo "::error::no Mach-O executable under $app"; exit 1; }

if [ "$fail" -ne 0 ]; then
  echo "::error::Sentry must not reach a production build; see EXCLUDED_PACKAGES in the workflow"
  exit 1
fi
echo "no Sentry in $(basename "$app"): not bundled, no symbols in $scanned executables"
