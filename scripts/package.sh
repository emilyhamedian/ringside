#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

# Build ringside.plasmoid from the committed package/ tree, for a release
# or for kpackagetool6 --install. Uncommitted changes are left out.

cd "$(dirname "$0")/.."

git archive --format=zip --output ringside.plasmoid HEAD:package
echo ringside.plasmoid
