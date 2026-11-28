package com.jmk.hud;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

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
    private static final String VER = "0.3.2";
    private static final String SRC = "cp";
    /** How long the display's hook waits for the service's answer before it leaves the display as drawn for now; not how long an answer stays valid. */
    private static final int ASK_MS = 300;
    /** How long the question itself may wait for the answer on its own thread: a late answer is an event and is applied when it comes. */
    private static final int LATE_MS = 5000;
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
    private static Handler handler;
    private static Runnable recheck;
    private static String pendingWhy, pendingTrig;
    private static HookClient askClient, noteClient;
    private static long noteAt, hourAt;
    private static int hourCount;
    private static int canRefresh = -1;
    private static boolean firstSeen;
    private static boolean noAnswer;                       // the display is held without any answer from the service
    private static long gen;                               // bumped by every new state and every end: an answer of an older one is stale
    private static final AtomicBoolean INFLIGHT = new AtomicBoolean();

    private Keep() { }

    public static void state(int st) {
        try {
            long now = SystemClock.elapsedRealtime();
            long since;
            boolean first;
            synchronized (LOCK) {
                first = !firstSeen && st != 0;
                if (first) firstSeen = true;
                since = lastStAt == 0 ? 0 : now - lastStAt;
                boolean changed = st != lastSt;
                lastSt = st;
                lastStAt = now;
                if (st != 0) {
                    live = true;
                    held = false;
                    asks = 0;
                    noAnswer = false;
                    gen++;
                    pendingWhy = null;
                    pendingTrig = null;
                    cancel();
                }
                if (!changed && !first) return;
            }
            if (first) restartAsk();
            note(st, since, st == 0 ? "state-0" : "state");
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    /**
     * The first route state this process sees: if DiPO started in the middle of a live phone session, the service knows and may answer refresh
     * (the route guidance is restarted, the phone sends it all again). One question per process, driven by that state, no timer. The answer
     * never ends anything.
     */
    private static void restartAsk() {
        try {
            boolean before;
            synchronized (LOCK) { before = refreshed; }
            ask("restart", 0);
            boolean after;
            synchronized (LOCK) { asks = 0; after = refreshed; }
            if (!before && after) Evt.end("restart", "cp", null);   // counted only when the restart of the route updates really ran
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    public static int zero(Object stockHolder) {
        try {
            synchronized (LOCK) {
                if (stockHolder != null) holder = stockHolder;
                if (!live) { endsBy("phone-stop", null); return 0; }
                if (held && !noAnswer) return 1;
            }
            // not yet held, or held without any answer: ask (again, once per route update) until an answer comes
            int act = ask("zero", 0);
            boolean firstNone;
            synchronized (LOCK) {
                if (act == DROP) { live = false; held = false; noAnswer = false; endsBy("phone-stop", null); return 0; }
                firstNone = act == NONE && !noAnswer;
                held = true;
                noAnswer = act == NONE;
            }
            if (firstNone) Evt.end("other", "cp", "core-absent");   // counted, so a missing service shows (the display is left as drawn)
            Log.i(TAG, "Route: state 0 kept (" + (act == NONE ? "no answer: left as drawn, asked again with the next update" : "answer") + ")");
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
            if (act == DROP) { endsBy("other", "silence"); return 1; }
            return 0;
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
                noAnswer = false;
                gen++;
                pendingWhy = null;
                pendingTrig = null;
                cancel();
            }
            note(-1, since, word);
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    private static int ask(final String why, long quietMs) {
        if (hotspotBusy()) return NONE;
        if (!INFLIGHT.compareAndSet(false, true)) return NONE;   // an earlier question has no answer yet: it lands by itself when it comes
        long now = SystemClock.elapsedRealtime();
        final int n;
        int since;
        final boolean can = canRefresh();
        boolean did;
        final long gen0;
        synchronized (LOCK) {
            n = ++asks;
            since = (int) Math.min(Integer.MAX_VALUE, lastStAt == 0 ? 0 : now - lastStAt);
            did = refreshed;
            gen0 = gen;
        }
        final Map<String, String> f = new LinkedHashMap<String, String>();
        f.put("src", SRC);
        f.put("why", why);
        f.put("st", String.valueOf(lastSt));
        f.put("quiet_ms", String.valueOf(Math.min(Integer.MAX_VALUE, quietMs)));
        f.put("since_state_ms", String.valueOf(since));
        f.put("n", String.valueOf(n));
        f.put("refresh", did ? "1" : "0");
        f.put("can_refresh", can ? "1" : "0");
        final CountDownLatch done = new CountDownLatch(1);
        final AtomicInteger who = new AtomicInteger(0);   // 0 waiting, 1 the hook took the answer, 2 the hook gave up (the answer is applied by the thread)
        final HookClient.Reply[] res = new HookClient.Reply[1];
        Thread th = new Thread(new Runnable() {
            public void run() {
                HookClient.Reply r = null;
                try {
                    r = client(true).ask(Lex.get(Lex.KEEP_ASK), f, LATE_MS);
                } catch (Throwable e) {
                    // no answer
                } finally {
                    INFLIGHT.set(false);
                }
                res[0] = r;
                if (who.compareAndSet(0, 1)) done.countDown();
                else late(why, r, n, gen0, can);
            }
        }, "jmkhud-ask");
        th.setDaemon(true);
        th.start();
        boolean in = false;
        try { in = done.await(ASK_MS, TimeUnit.MILLISECONDS); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        if (!in && who.compareAndSet(0, 2)) {
            Log.i(TAG, "Route: ask " + why + " st=" + lastSt + " n=" + n + " -> none (no answer within " + ASK_MS + " ms: left as drawn for now)");
            return NONE;
        }
        HookClient.Reply r = res[0];
        int[] pa = parse(r);
        int act = pa[0];
        long again = pa[1];
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

    /** {act, recheck_ms} of a reply: act NONE when there is no usable answer. */
    private static int[] parse(HookClient.Reply r) {
        int act = NONE;
        long again = 0;
        if (r != null && "answered".equals(r.how) && r.frame != null && "ok".equals(r.frame.type)) {
            String a = r.frame.get("act", "");
            if ("keep".equals(a)) act = KEEP;
            else if ("drop".equals(a)) act = DROP;
            else if ("refresh".equals(a)) act = REFRESH;
            try { again = Long.parseLong(r.frame.get("recheck_ms", "0")); } catch (NumberFormatException e) { again = 0; }
        }
        return new int[] { act, (int) Math.min(Integer.MAX_VALUE, again) };
    }

    /**
     * The answer came after the hook had given up (an event of its own): applied now if nothing happened since (the same route, no new state, no end).
     * A drop at a state 0 ends the display; a refresh restarts the route updates (once per route); a keep only clears "no answer".
     */
    private static void late(String why, HookClient.Reply r, int n, long gen0, boolean can) {
        try {
            int[] pa = parse(r);
            int act = pa[0];
            Log.i(TAG, "Route: late answer " + why + " n=" + n + " -> " + (act == KEEP || act == REFRESH ? "keep" : act == DROP ? "drop" : "none")
                    + (r == null ? "" : " how=" + r.how + " ms=" + r.ms));
            if (act == NONE) return;
            Object u = null;
            boolean end = false, go = false;
            synchronized (LOCK) {
                if (gen0 != gen) { Log.i(TAG, "Route: late answer " + why + " is stale (a state or an end came since)"); return; }
                if (act == DROP && "zero".equals(why) && live && held) { live = false; held = false; noAnswer = false; u = holder; end = true; }
                else if (act != DROP) { noAnswer = false; go = act == REFRESH && can && !refreshed; if (go) refreshed = true; }
            }
            if (end) { endsBy("phone-stop", "late"); end(u); return; }
            if (go) { refresh(); if ("restart".equals(why)) Evt.end("restart", "cp", null); }
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    private static void schedule(long ms) {
        synchronized (LOCK) {
            cancel();
            if (handler == null) handler = new Handler(Looper.getMainLooper());
            recheck = new Runnable() {
                public void run() { due(); }
            };
            handler.postDelayed(recheck, Math.max(1, ms));
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
            if (act == DROP) {
                synchronized (LOCK) { held = false; live = false; }
                endsBy("phone-stop", "recheck");
                end(u);
            }
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    private static void cancel() {
        if (recheck != null && handler != null) handler.removeCallbacks(recheck);
        recheck = null;
    }

    /** The cause the next blank is counted under (set just before the stock end runs; EndLog.blank takes it). */
    static void endsBy(String why, String trig) {
        synchronized (LOCK) { pendingWhy = why; pendingTrig = trig; }
    }

    /** The pending cause as {why, trig}, taken (cleared) once; null when none was set. */
    static String[] takeCause() {
        synchronized (LOCK) {
            if (pendingWhy == null) return null;
            String[] c = new String[] { pendingWhy, pendingTrig };
            pendingWhy = null;
            pendingTrig = null;
            return c;
        }
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
        client(false).tell(Lex.get(Lex.KEEP_NOTE), f);
    }

    /** The question and the note each have their own client (own helper thread, own gate): one cannot hold the other up. */
    private static HookClient client(boolean question) {
        synchronized (LOCK) {
            if (question) {
                if (askClient == null) askClient = make();
                return askClient;
            }
            if (noteClient == null) noteClient = make();
            return noteClient;
        }
    }

    private static HookClient make() {
        return new HookClient(LocalSockets.connector(NAME), new Clock() {
            public long el() { return SystemClock.elapsedRealtime(); }
        }, new jmkhud.link.Log() {
            public void line(String s) { Log.i(TAG, s); }
        }, ROLE, VER);
    }
}
