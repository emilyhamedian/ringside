#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Build ringside.plasmoid from the committed package/ tree, for a release
# or for kpackagetool6 --install. Uncommitted changes are left out.

cd "$(dirname "$0")/.."

git archive --format=zip --output ringside.plasmoid HEAD:package
echo ringside.plasmoid
