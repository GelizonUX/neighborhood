#!/bin/zsh
# Rebuilds the browser version of the game and uploads it, so the play link
# shows the latest changes a minute or two later.
# Usage:  ./publish.sh "what changed"
set -e
cd "$(dirname "$0")"
GODOT="../Tools/Godot.app/Contents/MacOS/Godot"
export PATH="$PWD/../Tools/gh:$PATH"

"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" docs/index.html 2>&1 | grep -iE "^error" || true
test -s docs/index.wasm || { echo "Web export failed"; exit 1; }
find . -name '._*' -not -path './.git/*' -delete

git add -A
git commit -q -m "${1:-Update game}" || echo "Nothing new to commit"
git push -q
echo "Published."
