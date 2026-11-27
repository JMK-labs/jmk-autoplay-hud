package com.jmk.hud;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;

import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import jmkhud.link.Clock;
import jmkhud.link.Frame;
import jmkhud.link.HookClient;
import jmkhud.link.Lex;
import jmkhud.link.android.LocalSockets;

/**
 * jmk-autoplay-hud 0.2.5 (AGPL-3.0, as this package; JMK's own code).
 * HUD DiPO bridge: a local JMK service (`jmk.core`) decides how the route display proceeds.
 * Every call is inside try / catch Throwable: a missing class or any exception means the hook does nothing.
 */
public final class Keep {
    private static final String TAG = "JMKHUD";
    private static final String NAME = "jmk.core";
    private static final String ROLE = "hud-dipo";
    private static final String VER = "0.2.5";
    private static final String SRC = "cp";
    private static final int ASK_MS = 300;
    private static final long QUIET_MS = 60000;
    private static final long NOTE_GAP_MS = 1000;
    private static final long NOTE_HOUR_MS = 3600000;
    private static final int NOTE_HOUR_MAX = 60;

    private static final int NONE = 0, KEEP = 1, DROP = 2, REFRESH = 3;

    private static final Object LOCK = new Object();
    private static boolean live;
    private static boolean held;
    private static boolean refreshed;
    private static int asks;
    private static int lastSt = -1;
    private static long lastStAt;
    private static long silenceAskAt;
    private static Object holder;
    private static Timer timer;
    private static TimerTask recheck;
    private static long noteAt, hourAt;
    private static int hourCount;
    private static int canRefresh = -1;

    private Keep() { }

    public static void state(int st) {
        try {
            long now = SystemClock.elapsedRealtime();
            long since;
            synchronized (LOCK) {
                since = lastStAt == 0 ? 0 : now - lastStAt;
                boolean changed = st != lastSt;
                lastSt = st;
                lastStAt = now;
                if (st != 0) {
                    live = true;
                    held = false;
                    asks = 0;
                    cancel();
                }
                if (!changed) return;
            }
            note(st, since, st == 0 ? "state-0" : "state");
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    public static int zero(Object stockHolder) {
        try {
            synchronized (LOCK) {
                if (stockHolder != null) holder = stockHolder;
                if (!live) return 0;
                if (held) return 1;
            }
            int act = ask("zero", 0);
            synchronized (LOCK) {
                if (act == DROP || act == NONE) { live = false; return 0; }
                held = true;
            }
            return 1;
        } catch (Throwable t) {
            return 0;
        }
    }

    public static int beat(long quietMs) {
        try {
            if (quietMs < QUIET_MS) return 0;
            long now = SystemClock.elapsedRealtime();
            synchronized (LOCK) {
                if (now < silenceAskAt) return 0;
                silenceAskAt = now + QUIET_MS;
            }
            int act = ask("silence", quietMs);
            return act == DROP ? 1 : 0;
        } catch (Throwable t) {
            return 0;
        }
    }

    public static void ended(String word) {
        try {
            long since;
            synchronized (LOCK) {
                long now = SystemClock.elapsedRealtime();
                since = lastStAt == 0 ? 0 : now - lastStAt;
                live = false;
                held = false;
                refreshed = false;
                asks = 0;
                silenceAskAt = 0;
                cancel();
            }
            note(-1, since, word);
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    private static int ask(String why, long quietMs) {
        if (hotspotBusy()) return NONE;
        long now = SystemClock.elapsedRealtime();
        int n, since;
        boolean can = canRefresh();
        boolean did;
        synchronized (LOCK) {
            n = ++asks;
            since = (int) Math.min(Integer.MAX_VALUE, lastStAt == 0 ? 0 : now - lastStAt);
            did = refreshed;
        }
        Map<String, String> f = new LinkedHashMap<String, String>();
        f.put("src", SRC);
        f.put("why", why);
        f.put("st", String.valueOf(lastSt));
        f.put("quiet_ms", String.valueOf(Math.min(Integer.MAX_VALUE, quietMs)));
        f.put("since_state_ms", String.valueOf(since));
        f.put("n", String.valueOf(n));
        f.put("refresh", did ? "1" : "0");
        f.put("can_refresh", can ? "1" : "0");
        HookClient.Reply r = client().ask(Lex.get(Lex.KEEP_ASK), f, ASK_MS);
        int act = NONE;
        long again = 0;
        if (r != null && "answered".equals(r.how) && r.frame != null && "ok".equals(r.frame.type)) {
            String a = r.frame.get("act", "");
            if ("keep".equals(a)) act = KEEP;
            else if ("drop".equals(a)) act = DROP;
            else if ("refresh".equals(a)) act = REFRESH;
            try { again = Long.parseLong(r.frame.get("recheck_ms", "0")); } catch (NumberFormatException e) { again = 0; }
        }
        if (act == REFRESH) {
            boolean go;
            synchronized (LOCK) {
                go = can && !refreshed;
                if (go) refreshed = true;
            }
            if (go) refresh();
            act = KEEP;
        }
        Log.i(TAG, "Route: ask " + why + " st=" + lastSt + " n=" + n + " -> " + (act == KEEP ? "keep" : act == DROP ? "drop" : "none")
                + (r == null ? "" : " how=" + r.how + " ms=" + r.ms) + (again > 0 ? " recheck=" + again : ""));
        if (act == KEEP && "zero".equals(why) && again > 0) schedule(again);
        return act;
    }

    private static void schedule(long ms) {
        synchronized (LOCK) {
            cancel();
            if (timer == null) timer = new Timer("jmkhud-keep", true);
            recheck = new TimerTask() {
                public void run() { due(); }
            };
            timer.schedule(recheck, Math.max(1, ms));
        }
    }

    private static void due() {
        try {
            Object u;
            synchronized (LOCK) {
                recheck = null;
                if (!held || !live) return;
                u = holder;
            }
            int act = ask("zero", 0);
            if (act == DROP || act == NONE) {
                synchronized (LOCK) { held = false; live = false; }
                end(u);
            }
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    private static void cancel() {
        if (recheck != null) { recheck.cancel(); recheck = null; }
    }

    private static void end(final Object u) {
        if (u == null) return;
        new Handler(Looper.getMainLooper()).post(new Runnable() {
            public void run() {
                try {
                    Method m = u.getClass().getMethod("nS");
                    m.invoke(u);
                } catch (Throwable t) {
                    Log.i(TAG, "Route: end failed");
                }
            }
        });
    }

    private static boolean canRefresh() {
        synchronized (LOCK) {
            if (canRefresh < 0) canRefresh = findHolder() != null ? 1 : 0;
            return canRefresh == 1;
        }
    }

    private static Object findHolder() {
        try {
            Class<?> c = Class.forName("com.daudio.app.dipo.e.u");
            Field f = c.getDeclaredField("leafiaOwner");
            f.setAccessible(true);
            Object o = f.get(null);
            if (o == null) return null;
            o.getClass().getMethod("leafiaRestartRouteGuidance");
            return o;
        } catch (Throwable t) {
            return null;
        }
    }

    private static void refresh() {
        final Object o = findHolder();
        if (o == null) return;
        Thread t = new Thread(new Runnable() {
            public void run() {
                try {
                    o.getClass().getMethod("leafiaRestartRouteGuidance").invoke(o);
                } catch (Throwable e) {
                    Log.i(TAG, "Route: refresh failed");
                }
            }
        }, "jmkhud-refresh");
        t.setDaemon(true);
        t.start();
        Log.i(TAG, "Route: refresh");
    }

    private static boolean hotspotBusy() {
        try {
            Class<?> c = Class.forName("com.jmk.hud.Callout");
            return Boolean.TRUE.equals(c.getMethod("busy").invoke(null));
        } catch (Throwable t) {
            return false;
        }
    }

    private static void note(int st, long sinceMs, String word) {
        long now = SystemClock.elapsedRealtime();
        synchronized (LOCK) {
            if (now - noteAt < NOTE_GAP_MS && noteAt != 0) return;
            if (hourAt == 0 || now - hourAt >= NOTE_HOUR_MS) { hourAt = now; hourCount = 0; }
            if (hourCount >= NOTE_HOUR_MAX) return;
            hourCount++;
            noteAt = now;
        }
        Map<String, String> f = new LinkedHashMap<String, String>();
        f.put("src", SRC);
        f.put("st", String.valueOf(st));
        f.put("since_state_ms", String.valueOf(Math.min(Integer.MAX_VALUE, sinceMs)));
        f.put("reason", word);
        client().tell(Lex.get(Lex.KEEP_NOTE), f);
    }

    private static HookClient client() {
        return HookClient.get(LocalSockets.connector(NAME), new Clock() {
            public long el() { return SystemClock.elapsedRealtime(); }
        }, new jmkhud.link.Log() {
            public void line(String s) { Log.i(TAG, s); }
        }, ROLE, VER);
    }
}
