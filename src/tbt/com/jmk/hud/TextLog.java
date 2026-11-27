package com.jmk.hud;

import java.util.HashMap;

import android.util.Log;

/**
 * jmk-autoplay-hud 0.2.2 (AGPL-3.0, as this package): one log line when the length of a text handed to the car's cluster interface
 * changes: the number of characters and the byte count (UTF-16 and UTF-8). The text itself is never written.
 */
public final class TextLog {
    private static final String TAG = "JMKHUD";
    private static final HashMap<String, String> LAST = new HashMap<String, String>();

    private TextLog() { }

    public static void turn(String s) { one("turn", s, -1); }

    public static void dest(String s) { one("dest", s, -1); }

    public static void cross(String s) { one("cross", s, -1); }

    /** The list frame: {@code bytes16} is the UTF-16 byte count before the frame's cap. */
    public static void hud(String s, int bytes16) { one("hud", s, bytes16); }

    private static void one(String site, String s, int bytes16) {
        try {
            int chars = s == null ? -1 : s.length();
            int u8 = s == null ? -1 : s.getBytes("UTF-8").length;
            int u16 = bytes16 >= 0 ? bytes16 : (s == null ? -1 : 2 * chars);
            String now = chars + " " + u16 + " " + u8;
            synchronized (LAST) {
                if (now.equals(LAST.get(site))) return;
                LAST.put(site, now);
            }
            Log.i(TAG, "Text: " + site + " chars=" + chars + " utf16=" + u16 + " utf8=" + u8);
        } catch (Throwable t) {
            // a log line is never worth a failure
        }
    }
}
