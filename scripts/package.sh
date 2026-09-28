#!/usr/bin/env bash
set -euo pipefail

# Build ringside.plasmoid from the committed package/ tree, for a release
# or for kpackagetool6 --install. Uncommitted changes are left out.

cd "$(dirname "$0")/.."

git archive --format=zip --output ringside.plasmoid HEAD:package
echo ringside.plasmoid
