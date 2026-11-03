#!/bin/bash
# Publishes a release that installed copies of Luminary pick up through Check for Updates:
#   1. bump VERSION and BUILD in scripts/make-app.sh, write dist/release-notes-<version>.md, commit
#   2. ./scripts/release.sh
# It builds the DMG, signs it with the Sparkle key in this Mac's Keychain, pushes the code, creates the GitHub
# release with the DMG, then adds the release to appcast.xml and pushes that (in this order, so the feed never
# points at a file that isn't uploaded yet).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 '^VERSION=' scripts/make-app.sh | cut -d'"' -f2)
BUILD=$(grep -m1 '^BUILD=' scripts/make-app.sh | cut -d'"' -f2)
TAG="v$VERSION"
DMG="dist/Luminary-$VERSION.dmg"
NOTES="dist/release-notes-$VERSION.md"

[ -f "$NOTES" ] || { echo "Write $NOTES first (shown on GitHub and in the update window)."; exit 1; }
[ -z "$(git status --porcelain -- Sources Package.swift scripts)" ] || { echo "Commit your changes first."; exit 1; }
if grep -q "<sparkle:version>$BUILD</sparkle:version>" appcast.xml; then
  echo "Build $BUILD is already in appcast.xml. Bump BUILD (and VERSION) in scripts/make-app.sh."; exit 1
fi

./scripts/make-app.sh --package
SIGNATURE=$(.build/artifacts/sparkle/Sparkle/bin/sign_update --account luminary "$DMG") # sparkle:edSignature="…" length="…"

git push
gh release create "$TAG" "$DMG" --title "Luminary $VERSION" --notes-file "$NOTES"

python3 -I - "$VERSION" "$BUILD" "$TAG" "$SIGNATURE" "$NOTES" <<'PY'
import html, re, sys
from email.utils import formatdate
version, build, tag, signature, notes_path = sys.argv[1:]
notes = open(notes_path, encoding="utf-8").read()
# Plain text for Sparkle's update window: drop Markdown markup, keep the words.
notes = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", notes)
notes = re.sub(r"[*`#]", "", notes).strip()
url = f"https://github.com/portwhy/Luminary/releases/download/{tag}/Luminary-{version}.dmg"
item = f"""    <item>
      <title>Luminary {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/portwhy/Luminary/releases/tag/{tag}</sparkle:fullReleaseNotesLink>
      <description sparkle:format="plain-text"><![CDATA[{notes}]]></description>
      <enclosure url="{html.escape(url)}" {signature} type="application/octet-stream"/>
    </item>
"""
marker = "    <!-- releases (newest first) -->\n"
feed = open("appcast.xml", encoding="utf-8").read()
assert marker in feed, "appcast.xml is missing its marker line"
open("appcast.xml", "w", encoding="utf-8").write(feed.replace(marker, marker + item, 1))
PY

git add appcast.xml
git commit -q -m "Release $VERSION" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
echo "Released $VERSION: installed copies will offer it within a day, or right away with Check for Updates."
