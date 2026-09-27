#!/bin/sh
# Stands in for ringside-info.sh in tst_monitor.qml: a laptop with a
# discrete GPU that stays asleep, so the test never reads real hardware.
case ${1:-} in
    static)
        cat <<'JSON'
{"plasma":"6.7.5","cpu":{"model":"AMD Ryzen 7 7840HS w/ Radeon 780M Graphics","cores":8,"threads":4,"ids":[0,1,2,3],"tempLabel":"Tctl"},"memory":{"type":"DDR5","speed":4800,"modules":[17179869184,17179869184]},"swap":["zram"],"gpus":[{"id":"gpu97","bdf":"0000:fe:00.0","vendor":"1002","kind":"discrete","name":"AMD Radeon RX 7700S","pciName":"","runtimePm":true,"autosuspendMs":5000},{"id":"gpu98","bdf":"0000:ff:00.0","vendor":"1002","kind":"integrated","name":"AMD Radeon 780M Graphics","pciName":"","runtimePm":false,"autosuspendMs":0}],"disks":["vdz","vdy"],"defaultInterface":"eth9","root":{"uuid":"00000000-0000-0000-0000-000000000000","disk":"vdz","tempSensor":""}}
JSON
        ;;
    pm)
        shift
        for bdf in "$@"; do
            printf '%s suspended auto\n' "$bdf"
        done
        ;;
    route) echo eth9 ;;
esac
