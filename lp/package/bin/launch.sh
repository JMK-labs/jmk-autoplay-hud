#!/system/bin/sh
# NEMESIS Launch: the JMK MAP menu's AutoPlay screen (its HUD card holds this add-on's settings and status)
exec /system/bin/am startservice -n com.jmk.map/jmkmap.MenuService --es screen autoplay
