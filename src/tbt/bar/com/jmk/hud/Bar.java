package com.jmk.hud;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;

/**
 * jmk-autoplay-hud 0.1.33 (AGPL-3.0, as this package): the decisions of the cluster's near-turn distance bar, with no
 * Android in it (the Android side is BarOut for the phone processes and NaviBar for the navigation process; test/bar
 * runs this class on the JVM).
 *
 * The cluster draws the bar from the barGraphLevel of the trap-info frame (NavigationCluster.updateTBTTrapInfo /
 * updateTBTTrapInfoNew), which only the stock navigation sends. The phone processes (HKMC_GPM for Android Auto,
 * HKMC_DiPO for CarPlay) tell the bar of the turn frame they send (10..90, 0 far, NONE = no phone bar) by broadcast
 * ACTION; the navigation process (HKMC_Navi_ExSL) puts that value into the bar field of the stock trap-info frames
 * while the phone guides, and sends the last stock frame again with the new bar when the phone value changes.
 *
 * Ported from an AGPL-3.0 Korean-firmware mod code base (phone bar, 2.4.5 generation):
 * the phone-bar sender and navi side, the trap-info arguments and the bar output.
 * Ported, adapted: our own action name, the values and intervals
 * as there, no HMG-API.
 */
public final class Bar {
    private Bar() {
    }

    /** the broadcast (value only: the int extra "bar") */
    public static final String ACTION = "com.jmk.hud.BAR";
    public static final String EXTRA_BAR = "bar";
    /** the phone sets no bar (guidance ended, nothing to show): the stock bar goes out */
    public static final int NONE = -1;
    /** the same value is sent again after this while a bar is shown (the navigation process may start later) */
    public static final long RESEND_MS = 10000;
    /** no broadcast for this long: the phone value is dropped (the last safety; a quiet AA light sends nothing) */
    public static final long EXPIRE_MS = 180000;
    /** the trap-info bar field's range (0..100; outside it is 0 on the cluster) */
    public static final int MAX = 100;
    /** the least gap between two trap frames the navigation side sends itself */
    public static final long MIN_GAP_MS = 200;

    /** Android Auto: the bar of LeafiaTurn.standard's result {display type, angle, bar, lane}; no result: NONE */
    public static int aaBar(int[] r) {
        if (r == null || r.length < 3) return NONE;
        return r[2] < 0 || r[2] > MAX ? NONE : r[2];
    }

    /** CarPlay: the bar of the turn frame (display type 8 = nothing to show: NONE) */
    public static int cpBar(int display, int bar) {
        if (display == 8) return NONE;
        return bar < 0 || bar > MAX ? NONE : bar;
    }

    /** the phone processes: send a value when it changed, or RESEND_MS after the last one while a bar is shown */
    public static final class Sender {
        private int last = Integer.MIN_VALUE;
        private long at;

        /** whether to send this value now (and it is remembered when so) */
        public boolean due(int bar, long now) {
            if (bar == last && (bar == NONE || now - at < RESEND_MS)) return false;
            last = bar;
            at = now;
            return true;
        }
    }

    /**
     * The navigation process: what bar goes into the stock trap-info frame, and when the last stock frame is sent
     * again. Each of onStock (a stock trap-info call), onBar (a broadcast) and check (a clock tick) returns the bar
     * to send again (Integer) or null. A stock frame never seen is never made up (cameras and speed limits are not
     * invented).
     */
    public static final class Navi {
        int phoneBar = NONE;
        long barAt;
        /** the last trap frame that went out carried the phone's bar */
        boolean overriding;
        /** the last bar the stock navigation sent (what goes back) */
        int stockBar;
        boolean seen;

        boolean active(boolean phone, long now) {
            return phone && phoneBar != NONE && now - barAt < EXPIRE_MS;
        }

        /** a stock trap-info call: the bar to send really (the phone's or the stock one) */
        public int onStock(int stock, boolean phone, long now) {
            seen = true;
            stockBar = stock;
            overriding = active(phone, now);
            return overriding ? phoneBar : stock;
        }

        /** a broadcast: the bar to send again, or null */
        public Integer onBar(int bar, boolean phone, long now) {
            if (bar != NONE && (bar < 0 || bar > MAX)) bar = NONE;   // out of range: the stock value
            boolean changed = bar != phoneBar;
            phoneBar = bar;
            barAt = now;
            if (!seen) return null;
            if (active(phone, now)) {
                if (!changed && overriding) return null;
                overriding = true;
                return bar;
            }
            return restore();
        }

        /** a tick: the phone stopped guiding or the broadcasts stopped: the stock bar goes back */
        public Integer check(boolean phone, long now) {
            if (!overriding || active(phone, now)) return null;
            return restore();
        }

        /** the bar the cluster should have now */
        public int current() {
            return overriding ? phoneBar : stockBar;
        }

        public boolean isOverriding() {
            return overriding;
        }

        public boolean hasPhoneBar() {
            return phoneBar != NONE;
        }

        private Integer restore() {
            if (!overriding) return null;
            overriding = false;
            return stockBar;
        }
    }

    // ------------------------------------------------------------------------------------------ trap-info arguments
    /** updateTBTTrapInfo(17 ints): the place of barGraphLevel (stock signature order) */
    public static final int BAR_ARG = 11;
    public static final int INT_ARGS = 17;
    public static final String BAR_FIELD = "barGraphLevel";

    /** the object form (NaviTbtTrapInfo) may be copied only when every instance field is a public non-final int */
    public static Field barField(Class<?> info) {
        Field bar = null;
        for (Class<?> c = info; c != null && c != Object.class; c = c.getSuperclass()) {
            for (Field f : c.getDeclaredFields()) {
                int m = f.getModifiers();
                if (Modifier.isStatic(m) || f.isSynthetic()) continue;
                if (!Modifier.isPublic(m) || Modifier.isFinal(m) || f.getType() != int.class) return null;
                if (BAR_FIELD.equals(f.getName()) && c == info) bar = f;
            }
        }
        return bar;
    }

    /** the bar of the 17-int form, -1 when it cannot be used (not 17 ints, or outside 0..100) */
    public static int intBar(Object[] a) {
        if (a == null || a.length != INT_ARGS || !(a[BAR_ARG] instanceof Integer)) return -1;
        int v = (Integer) a[BAR_ARG];
        return v < 0 || v > MAX ? -1 : v;
    }

    /** a copy of the object form: a new object, every instance int field moved */
    public static Object copy(Object o) throws Exception {
        Class<?> c = o.getClass();
        Object n = c.newInstance();
        for (Field f : c.getFields()) {
            if (Modifier.isStatic(f.getModifiers()) || f.getType() != int.class) continue;
            f.setInt(n, f.getInt(o));
        }
        return n;
    }

    /** the arguments with only the bar changed (the object form: a copy; the stock object is never touched) */
    public static Object[] withBar(Object[] a, boolean isNew, Field bar, int value) throws Exception {
        Object[] r = a.clone();
        if (isNew) {
            Object c = copy(a[0]);
            bar.setInt(c, value);
            r[0] = c;
        } else {
            r[BAR_ARG] = Integer.valueOf(value);
        }
        return r;
    }
}
