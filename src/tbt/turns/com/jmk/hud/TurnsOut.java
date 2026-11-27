package com.jmk.hud;

import android.os.SystemClock;
import android.util.Log;

import java.lang.reflect.Method;

/**
 * jmk-autoplay-hud 0.1.34 (AGPL-3.0, as this package): the hooks' side of the turn pictures (the decisions are Turns,
 * which carries the notice of what was ported from an AGPL-3.0 Korean-firmware mod code base (turn pictures, 2.4.8 generation),
 * AGPL-3.0; ported, adapted).
 * The hooks (turns.py):
 *
 *   HKMC_GPM (Android Auto)
 *     GpmNaviTBTManager.setRampDisplayType   mDisplayType = TurnsOut.aaFar(event, side, mDisplayType)
 *     LeafiaTurn.standard                    TurnsOut.aaNear(event, side, far icon, far direction, metres) in front
 *                                            of LeafiaStandard.format (a result is the near layout; null: Leafia's)
 *     GpmNaviTBTManager.updateTBTInfo        direction = TurnsOut.aaDir(result, direction); TurnsOut.aaIn(angle, far
 *                                            icon); TurnsOut.aaOut(event, side, display sent, direction sent)
 *   HKMC_DiPO bridge build (CarPlay)
 *     u.a (the route guidance update)        icon = TurnsOut.cpFar(u, component, route guidance, the table's number,
 *                                            the number after LeafiaCpStandard.projection)
 *     LeafiaCpStandard.format                native = TurnsOut.cpNear(LeafiaCpStandard.nativeTurn's result, facts)
 *     u.a, before the one updateTBTInfo send TurnsOut.cpSent(far icon, display sent, direction sent)
 *
 * Log (tag JMKHUD), one line when a turn's numbers or its pictures change (numbers only, no road or instruction text),
 * at most LOGS_MAX lines per LOG_WINDOW_MS:
 *   Turn: aa ev E side S angle A -> far F (rule) / near D @DIR (rule)
 *   Turn: cp type T side S junction J exit E state St -> far F (rule) / near D @DIR (rule)
 * "near none": the far picture is what is shown. The rules are Turns'.
 *
 * Nothing here ever throws into the stock code: a failure gives back the value as it came. The CarPlay hooks take no
 * lock of their own (cpNear runs inside LeafiaCpStandard's lock, cpFar takes that lock for the facts): no lock order.
 */
public final class TurnsOut {
    private static final String TAG = "JMKHUD";
    static final int LOGS_MAX = 120;
    static final long LOG_WINDOW_MS = 300000L;

    private TurnsOut() {
    }

    private static long logWindow;
    private static int logs;
    private static String lastLine;

    private static synchronized void line(String s) {
        if (s.equals(lastLine)) return;
        lastLine = s;
        long now = SystemClock.elapsedRealtime();
        if (now - logWindow >= LOG_WINDOW_MS) {
            logWindow = now;
            logs = 0;
        }
        if (logs >= LOGS_MAX) return;
        logs++;
        Log.i(TAG, "Turn: " + s);
    }

    // ------------------------------------------------------------------------------------------------ Android Auto
    private static int aaNearEvent = -1;
    private static boolean aaNearOurs;
    private static int aaAngle, aaFarIcon;

    /** GpmNaviTBTManager.setRampDisplayType, last: the far icon it chose -> the Korean stock number */
    public static int aaFar(int event, int side, int icon) {
        try {
            return Turns.aaFar(event, side, icon);
        } catch (Throwable t) {
            return icon;
        }
    }

    /**
     * LeafiaTurn.standard, in front of LeafiaStandard.format (same arguments): the near layout of an on-ramp or a
     * fork inside the window Near just set, or null (LeafiaStandard.format decides as before)
     */
    public static synchronized int[] aaNear(int event, int side, int far, int farDir, int meters) {
        try {
            int[] r = Turns.aaNear(event, side, meters, Near.window());
            aaNearEvent = event;
            aaNearOurs = r != null;
            return r;
        } catch (Throwable t) {
            aaNearOurs = false;
            return null;
        }
    }

    /** GpmNaviTBTManager.updateTBTInfo: the direction of the turn frame (22.5 / 337.5 for our fork layout) */
    public static float aaDir(int[] result, float dir) {
        try {
            return Turns.aaDir(result, dir);
        } catch (Throwable t) {
            return dir;
        }
    }

    /** GpmNaviTBTManager.updateTBTInfo: the phone's turn angle and the far icon of the turn being sent */
    public static synchronized void aaIn(int angle, int far) {
        aaAngle = angle;
        aaFarIcon = far;
    }

    /** GpmNaviTBTManager.updateTBTInfo: the phone's event and side, the display type and direction being sent */
    public static synchronized void aaOut(int event, int side, int display, float dir) {
        try {
            line(Turns.aaLine(event, side, aaAngle, aaFarIcon, Turns.aaFarRule(event, aaFarIcon), display, dir,
                    Turns.aaNearRule(aaNearEvent, aaNearOurs)));
        } catch (Throwable t) {
            // the turn frame goes on
        }
    }

    // ------------------------------------------------------------------------------------------------ CarPlay
    private static volatile Class<?> leafia;
    private static volatile Method factsM;
    private static volatile boolean factsFailed;
    private static volatile int[] cpFacts;
    private static volatile String cpFarRule = "none", cpNearRule = "none";

    /** LeafiaCpStandard.facts (private) of this update, under that class's own lock; null: none */
    private static int[] facts(Object u, Object id, Object c) {
        if (factsFailed) return null;
        try {
            Method m = factsM;
            Class<?> k = leafia;
            if (m == null || k == null) {
                k = Class.forName("com.leafia.kr.LeafiaCpStandard");
                m = k.getDeclaredMethod("facts", Object.class, Object.class, Object.class);
                m.setAccessible(true);
                leafia = k;
                factsM = m;
            }
            Object r;
            synchronized (k) {
                r = m.invoke(null, u, id, c);
            }
            return r instanceof int[] ? (int[]) r : null;
        } catch (NoSuchMethodException e) {
            factsFailed = true;
            Log.w(TAG, "Turn: cp facts not found, the far icon stays Leafia's: " + e);
            return null;
        } catch (ClassNotFoundException e) {
            factsFailed = true;
            Log.w(TAG, "Turn: cp facts not found, the far icon stays Leafia's: " + e);
            return null;
        } catch (Throwable t) {
            return null;
        }
    }

    /**
     * u.a, after LeafiaCpStandard.projection: table = the number before it (the build's table), icon = the number
     * after it. No facts or no route guidance (state 0): the number as it came.
     */
    public static int cpFar(Object u, Object id, Object c, int table, int icon) {
        try {
            int[] f = facts(u, id, c);
            cpFacts = f;
            cpNearRule = "none";
            if (f == null || f.length < 6 || f[5] == 0) {
                cpFarRule = "none";
                return icon;
            }
            String[] why = new String[1];
            int far = Turns.cpFar(f[0], f[1], f[2], f[3], f[4] != 0, f[5], table, icon, why);
            cpFarRule = why[0];
            return far;
        } catch (Throwable t) {
            cpFarRule = "none";
            return icon;
        }
    }

    /** LeafiaCpStandard.format, after nativeTurn: its result (null: none) and the facts it was made from */
    public static int[] cpNear(int[] nativeTurn, int[] facts) {
        try {
            if (facts == null || facts.length < 6) return nativeTurn;
            String[] why = new String[1];
            int[] r = Turns.cpNear(nativeTurn, facts[0], facts[1], facts[2], facts[3], facts[4] != 0, facts[5], why);
            cpNearRule = why[0];
            return r;
        } catch (Throwable t) {
            return nativeTurn;
        }
    }

    /** u.a, before the one updateTBTInfo send: the far icon, the display type and the direction being sent */
    public static void cpSent(int far, int display, float dir) {
        try {
            line(Turns.cpLine(cpFacts, far, cpFarRule, display, dir, cpNearRule));
        } catch (Throwable t) {
            // the turn frame goes on
        }
    }
}
