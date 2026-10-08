#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# fake-info.sh with a temperature sensor on the root disk, as
# ringside-info.sh reports one, for the restored disk temperature tests.
case ${1:-} in
    static) sh "$(dirname "$0")/fake-info.sh" static | sed 's|"tempSensor":""|"tempSensor":"disk/vdz/temperature"|' ;;
    *) exec sh "$(dirname "$0")/fake-info.sh" "$@" ;;
esac
