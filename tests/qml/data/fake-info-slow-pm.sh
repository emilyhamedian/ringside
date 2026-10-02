#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

if [ "${1:-}" = pm ]; then
    sleep 0.3
fi
exec sh "$(dirname "$0")/fake-info.sh" "$@"
