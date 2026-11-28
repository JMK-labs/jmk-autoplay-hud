#!/system/bin/sh
# migrate.meta verify=: exit 0 = no file of the legacy HUD's is left (every file stock, or never edited); 1 = not (the last line says what). Writes nothing.
here=${0%/*}
case "$here" in /*) ;; *) here=$(pwd)/$here ;; esac
exec sh "$here/legacy-restore.sh" --verify
