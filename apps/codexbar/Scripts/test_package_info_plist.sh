#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACKAGE_SCRIPT="$ROOT/Scripts/package_app.sh"
PLIST_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/codexbar-package-info-plist-script.XXXXXX")
CONFIG_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/codexbar-package-config-script.XXXXXX")
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexbar-package-info-plist.XXXXXX")
trap 'rm -f "$PLIST_SCRIPT" "$CONFIG_SCRIPT"; rm -rf "$TEMP_DIR"' EXIT

python3 - "$PACKAGE_SCRIPT" "$PLIST_SCRIPT" "$CONFIG_SCRIPT" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text()
start = script.index('cat > "$APP/Contents/Info.plist" <<PLIST')
end = script.index('\nPLIST\n', start) + len('\nPLIST\n')
Path(sys.argv[2]).write_text(script[start:end])
start = script.index('BUNDLE_ID="${CODEXBAR_BUNDLE_ID:')
end = script.index('\nresolve_package_signing_identity', start)
Path(sys.argv[3]).write_text(script[start:end])
PY

# A normal debug app remains isolated. An explicit local preview retains settings
# and app groups while disabling update checks, regardless of signing mode.
for signing in adhoc identity; do
  for preview in 0 1; do
    (
      LOWER_CONF=debug
      LOCAL_PREVIEW="$preview"
      SIGNING_MODE="$signing"
      CODEXBAR_BUNDLE_ID=org.example.codexbar
      source "$CONFIG_SCRIPT"
      [[ "$FEED_URL" == "" && "$AUTO_CHECKS" == false ]]
      if [[ "$preview" == 1 ]]; then
        [[ "$BUNDLE_ID" == org.example.codexbar ]]
        [[ "$WIDGET_BUNDLE_ID" == org.example.codexbar.widget ]]
        [[ "$APP_GROUP_BASE" == com.steipete.codexbar ]]
        [[ "$BUILD_CONFIGURATION" == local-debug-preview ]]
      else
        [[ "$BUNDLE_ID" == org.example.codexbar.debug ]]
        [[ "$WIDGET_BUNDLE_ID" == org.example.codexbar.debug.widget ]]
        [[ "$APP_GROUP_BASE" == com.steipete.codexbar.debug ]]
        [[ "$BUILD_CONFIGURATION" == debug ]]
      fi
    )
  done
done
for configuration in debug release; do
  if CODEXBAR_LOCAL_PREVIEW=1 CODEXBAR_BUNDLE_ID=com.steipete.codexbar \
    bash "$PACKAGE_SCRIPT" "$configuration" >"$TEMP_DIR/rejected.log" 2>&1; then
    echo "ERROR: upstream bundle identity accepted for a local preview" >&2
    exit 1
  fi
  grep -q 'CODEXBAR_LOCAL_PREVIEW requires debug and an explicit redistributor bundle ID' "$TEMP_DIR/rejected.log"
done
if CODEXBAR_LOCAL_PREVIEW=1 CODEXBAR_BUNDLE_ID=org.example.codexbar \
  bash "$PACKAGE_SCRIPT" release >"$TEMP_DIR/rejected.log" 2>&1; then
  echo "ERROR: release configuration accepted for a local preview" >&2
  exit 1
fi
grep -q 'CODEXBAR_LOCAL_PREVIEW requires debug and an explicit redistributor bundle ID' "$TEMP_DIR/rejected.log"

APP="$TEMP_DIR/CodexBar.app"
mkdir -p "$APP/Contents"
BUNDLE_ID=com.steipete.codexbar.test
MARKETING_VERSION=0.0.0
BUILD_NUMBER=0
FEED_URL=https://example.invalid/appcast.xml
AUTO_CHECKS=false
BUILD_TIMESTAMP=2026-01-01T00:00:00Z
GIT_COMMIT=test
BUILD_CONFIGURATION=local-debug-preview
APP_TEAM_ID=TESTTEAM
SPARKLE_PUBLIC_KEY=test-public-key
OPENCODEX_HUB_SNAPSHOT_PATH='~/.swift-app-state/opencodex-hub-accounts.json'
OPENCODEX_HUB_NAME=m5m1
OPENCODEX_HUB_MANAGEMENT_ORIGIN=https://hub.example
source "$PLIST_SCRIPT"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$APP/Contents/Info.plist"
fi
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

plist = plistlib.loads(Path(sys.argv[1]).read_bytes())
declarations = plist.get("UTExportedTypeDeclarations")
assert declarations == [{
    "UTTypeIdentifier": "com.steipete.codexbar.menu-layout-item",
    "UTTypeDescription": "CodexBar menu bar layout token",
    "UTTypeConformsTo": ["public.data"],
    "UTTypeTagSpecification": {},
}]
assert plist.get("CodexBarOpenCodexHubSnapshotPath") == "~/.swift-app-state/opencodex-hub-accounts.json"
assert plist.get("CodexBarOpenCodexHubName") == "m5m1"
assert plist.get("CodexBarOpenCodexHubManagementOrigin") == "https://hub.example"
assert plist.get("CodexBuildConfiguration") == "local-debug-preview"
PY

echo "Package Info.plist tests passed."
