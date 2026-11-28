package com.jmk.hud;

import android.util.Log;

/**
 * jmk-autoplay-hud 0.3.2 (AGPL-3.0, as this package; JMK's own code). One plain log line per event, for counting only:
 * no route data, no text. The settings service of this add-on reads the lines and keeps one count per day.
 * Every call is inside try / catch Throwable: a failure here never touches the display.
 */
public final class Evt {
    private static final String TAG = "JMKHUD";
    private static int seq;

    private Evt() { }

    /** The display ended. why: phone-stop, session-end, source-change, restart or other (then trig names the hook). proj: cp or aa. */
    public static void end(String why, String proj, String trig) {
        try {
            if (!ok(why)) why = "other";
            String line = "EVT tbt-end why=" + why + " proj=" + (ok(proj) ? proj : "cp");
            if ("other".equals(why)) line += " trig=" + (ok(trig) ? trig : "unknown");
            Log.i(TAG, line + " seq=" + next() + " pid=" + android.os.Process.myPid());
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    /** CarPlay sent the lane message (0x5204): one line per session with the count so far, never per message. */
    public static void lanes(int n, String app, String proj) {
        try {
            Log.i(TAG, "EVT cp-lanes n=" + n + " app=" + (ok(app) ? app : "?") + " proj=" + (ok(proj) ? proj : "cp")
                    + " seq=" + next() + " pid=" + android.os.Process.myPid());
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    private static int laneSeen, laneSent;
    private static boolean rawLogged;
    private static String app = "?";

    /** The phone's source name of the route (the display text, never sent: only a plain token or a short hash of it). */
    public static void source(String name) {
        try {
            app = token(name);
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    /**
     * Bytes of the iAP2 relay on their way from the phone to the car's iAP2 service (wireless CarPlay): counts the lane messages (message id
     * 0x5204; each starts with 0x40 0x40, a length and the id). Nothing is kept of the bytes. One line when the first one is seen,
     * the rest at the end of the session ({@link #sessionEnd}).
     */
    public static void iapIn(byte[] b, int len) {
        try {
            if (b == null || len < 6) return;
            if (len > b.length) len = b.length;
            int n = 0;
            for (int i = 0; i + 6 <= len; i++) {
                if (b[i] != 0x40 || b[i + 1] != 0x40 || b[i + 4] != 0x52 || b[i + 5] != 0x04) continue;
                int ml = ((b[i + 2] & 255) << 8) | (b[i + 3] & 255);
                if (ml >= 6 && ml <= 8192) n++;
            }
            if (n == 0) return;
            int first = 0;
            synchronized (Evt.class) {
                laneSeen += n;
                if (laneSent == 0) { laneSent = laneSeen; first = laneSeen; }
            }
            if (first > 0) lanes(first, app, "cp");
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    /** One decoded (or refused) raw lane message: res=ok|bad, which layout matched (a, b, ab or -), why a bad one was refused (a plain code). Counted per day by the settings service. */
    public static void raw(boolean ok, String layout, String why) {
        try {
            Log.i(TAG, "EVT cp-raw res=" + (ok ? "ok" : "bad") + " layout=" + (ok(layout) ? layout : "-") + " why=" + (ok(why) ? why : "-")
                    + " seq=" + next() + " pid=" + android.os.Process.myPid());
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    /** True once per session: the caller may log the raw bytes of the first lane message (RawLanes). */
    public static synchronized boolean firstRaw() {
        if (rawLogged) return false;
        rawLogged = true;
        return true;
    }

    /** The session ended: the lane messages since the first line, once; the count starts again. */
    public static void sessionEnd() {
        try {
            int rest;
            synchronized (Evt.class) {
                rest = laneSeen - laneSent;
                laneSeen = 0;
                laneSent = 0;
                rawLogged = false;
            }
            if (rest > 0) lanes(rest, app, "cp");
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    /** The stock restart of the route guidance after a source change, with a line for each step and a catch of its own. */
    public static void restart(Object owner) {
        try {
            Log.i(TAG, "Route: source restart start");
            owner.getClass().getMethod("leafiaRestartRouteGuidance").invoke(owner);
            Log.i(TAG, "Route: source restart done");
        } catch (Throwable t) {
            Log.i(TAG, "Route: source restart failed " + t.getClass().getName());
        }
    }

    private static synchronized int next() { return ++seq; }

    /** A plain token for the app: its letters and digits when it has only those, else "x" and eight hex digits of a hash. */
    static String token(String s) {
        if (s == null || s.length() == 0) return "?";
        StringBuilder b = new StringBuilder();
        boolean plain = true;
        for (int i = 0; i < s.length() && plain; i++) {
            char c = s.charAt(i);
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) b.append(Character.toLowerCase(c));
            else if (c == ' ' || c == '-') b.append('-');
            else plain = false;
        }
        if (plain && b.length() > 0) return b.length() > 24 ? b.substring(0, 24) : b.toString();
        int h = 0x811c9dc5;
        for (int i = 0; i < s.length(); i++) h = (h ^ s.charAt(i)) * 16777619;
        String x = Integer.toHexString(h);
        while (x.length() < 8) x = "0" + x;
        return "x" + x;
    }

    /** Plain words only: letters, digits, dash; at most 24 characters (an app name is cut to its safe letters). */
    private static boolean ok(String s) { return s != null && s.matches("[A-Za-z0-9-]{1,24}"); }
}
