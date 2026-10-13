#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Like fake-info.sh, but the discrete GPU, asleep as there, is NVIDIA's.
if [ "${1:-}" = static ]; then
    sh "$(dirname "$0")/fake-info.sh" static | sed 's/"bdf":"0000:fe:00.0","vendor":"1002"/"bdf":"0000:fe:00.0","vendor":"10de"/'
    exit 0
fi
exec sh "$(dirname "$0")/fake-info.sh" "$@"
