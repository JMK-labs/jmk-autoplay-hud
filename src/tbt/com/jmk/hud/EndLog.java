package com.jmk.hud;

import android.util.Log;

/**
 * jmk-autoplay-hud 0.3.2 (AGPL-3.0, as this package): one log line naming the caller; no text, no route data; one count line (Evt).
 */
public final class EndLog {
    private static final String TAG = "JMKHUD";

    private EndLog() { }

    public static void blank() {
        String word = "other";
        try {
            StackTraceElement[] st = new Throwable().getStackTrace();
            String why = "an unnamed path";
            for (int i = 0; i + 1 < st.length; i++) {
                if (!"sendHudBlank".equals(st[i].getMethodName())) continue;
                String n = st[i + 1].getMethodName();
                if ("disconnected".equals(n)) { why = "the session ended (disconnected)"; word = "session-end"; }
                else if ("leafiaSourceCheck".equals(n)) { why = "the route source name changed"; word = "source-change"; }
                else if (n != null && n.length() <= 3) { why = "stock method " + n; word = "stock-" + n.toLowerCase(); }
                break;
            }
            Log.i(TAG, "Guide end: CarPlay turn-by-turn blanked by " + why);
        } catch (Throwable t) {
            // a log line is never worth a failure
        }
        if (!word.matches("[a-z0-9-]{1,24}")) word = "other";
        String why, trig = null;
        String[] cause = Keep.takeCause();
        if (cause != null) { why = cause[0]; trig = cause[1]; }
        else if ("session-end".equals(word) || "source-change".equals(word)) why = word;
        else { why = "other"; trig = word; }
        Evt.end(why, "cp", trig);
        if ("session-end".equals(why)) Evt.sessionEnd();
        Keep.ended(word);
    }
}
