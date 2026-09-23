#!/usr/bin/env bash
# Exports the web build and publishes it to the gh-pages branch (GitHub Pages).
#
#   tools/deploy_web.sh            export + publish
#   GODOT=/path/to/godot tools/deploy_web.sh
#
# Needs the Godot web export templates installed and push access to origin.
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
OUT=build/web

echo "Exporting web build..."
mkdir -p "$OUT"
# Keep Godot from importing the exported files back into the project.
touch build/.gdignore
"$GODOT" --headless --path . --import < /dev/null > /dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html" < /dev/null > /dev/null 2>&1
test -f "$OUT/index.wasm" || { echo "Export failed (no index.wasm)."; exit 1; }

echo "Publishing to gh-pages..."
WORK="$(mktemp -d)"
trap 'git worktree remove --force "$WORK" > /dev/null 2>&1 || true' EXIT
if git ls-remote --exit-code --heads origin gh-pages > /dev/null 2>&1; then
	git fetch -q origin gh-pages
	git worktree add -q "$WORK" origin/gh-pages --detach
else
	git worktree add -q --detach "$WORK"
	git -C "$WORK" checkout -q --orphan gh-pages-new
	git -C "$WORK" rm -rq --cached . > /dev/null 2>&1 || true
fi
# Replace the site's contents with the fresh build.
find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r "$OUT"/. "$WORK"/
rm -f "$WORK"/*.import
touch "$WORK/.nojekyll"
git -C "$WORK" add -A
if git -C "$WORK" diff --cached --quiet; then
	echo "Nothing changed since the last deploy."
	exit 0
fi
git -C "$WORK" commit -q -m "Deploy web build from $(git rev-parse --short HEAD)"
git -C "$WORK" push -q origin HEAD:gh-pages
echo "Done. The site updates in a minute or two."
