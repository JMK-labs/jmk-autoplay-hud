package com.jmk.hud;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.util.Log;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * jmk-autoplay-hud 0.1.33 (AGPL-3.0, as this package): the navigation process's side of the cluster distance bar
 * (HKMC_Navi_ExSL). The stock navigation sends the trap-info frame (cameras, speed limits, the bar) with
 * NavigationCluster.updateTBTTrapInfo (17 ints) or updateTBTTrapInfoNew (NaviTbtTrapInfo); the cluster draws the bar
 * from it. The hooks (bar.py) sit in front of each of those calls the stock sender makes (not in front of the clear
 * frame NaviSpecialReceiver sends when the head unit wakes):
 *
 *   trap17(cluster, the 17 ints)    returns the bar to put in the call
 *   info(cluster, the object)       returns the object to pass (a copy with the bar changed, or the same one)
 *   after()                         right after the call
 *
 * While the phone guides (Android Auto: GpmManager.isGpmNaviGuidance, CarPlay: DiPOManager.isDiPOTurnByTurnMode) and
 * the phone's bar broadcast (BarOut, com.jmk.hud.BAR) is alive, only the bar of the stock frame is replaced. When the
 * phone value changes, the last stock frame is sent again with only the bar changed (never when no stock frame was
 * seen); when guidance ends (NONE), the broadcasts stop (Bar.EXPIRE_MS) or the phone no longer guides, the stock bar
 * goes back. Decisions: Bar.Navi. The sending again runs on this class's own thread, at most every Bar.MIN_GAP_MS.
 *
 * Log (tag JMKHUD): each override (stock bar -> phone bar), each revert, each frame sent again, the receiver.
 * Nothing here ever throws into the stock code.
 *
 * Ported from an AGPL-3.0 Korean-firmware mod code base (phone bar, 2.4.5 generation),
 * AGPL-3.0: the trap-bar side and the phone-guiding flag.
 * Ported, adapted: call-site hooks in place of method hooks (so a frame the sender sends again is not seen by the
 * hooks), reflection only, no HMG-API.
 */
public final class NaviBar {
    private static final String TAG = "JMKHUD";
    /** at most this many log lines per LOG_WINDOW_MS (a long drive keeps logging, a flood cannot) */
    private static final int LOGS_MAX = 60;
    private static final long LOG_WINDOW_MS = 300000L;

    private static final Bar.Navi NAVI = new Bar.Navi();

    /** the last stock call of one form (its target, method and a copy of the arguments) */
    private static final class Slot {
        Object target;
        Method method;
        Object[] args;
    }

    private static final Slot SLOT_INT = new Slot(), SLOT_NEW = new Slot();
    private static Field barField;
    /** the bar this thread's stock call really carried (checked in after()) */
    private static final ThreadLocal<Integer> SENT = new ThreadLocal<Integer>();
    private static long seq;
    private static long lastSendAt = -Bar.MIN_GAP_MS;
    private static boolean sendPosted, failSend, failStock;
    private static volatile boolean registered;
    /** the override last logged (phone bar, stock bar): the same pair is not logged again and again */
    private static int ovBar = -1, ovStock = -1;
    private static long registerTry = -1000000L;
    private static int logs;
    private static long logWindow = -1000000L;
    private static volatile Handler handler;

    private NaviBar() {
    }

    // ------------------------------------------------------------------------------------------------ hooks
    /** in front of updateTBTTrapInfo(17 ints): the bar to put in the call */
    public static int trap17(Object cluster, int a0, int a1, int a2, int a3, int a4, int a5, int a6, int a7, int a8,
                             int a9, int a10, int a11, int a12, int a13, int a14, int a15, int a16) {
        try {
            register();
            Object[] args = new Object[] { a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16 };
            Object[] w = stock(cluster, false, args, a11);
            return w == null ? a11 : (Integer) w[Bar.BAR_ARG];
        } catch (Throwable t) {
            fail(t);
            return a11;
        }
    }

    /** in front of updateTBTTrapInfoNew(object): the object to pass */
    public static Object info(Object cluster, Object info) {
        try {
            register();
            if (cluster == null || info == null) return info;
            Field f = barField;
            if (f == null || f.getDeclaringClass() != info.getClass()) {
                f = Bar.barField(info.getClass());
                if (f == null) {
                    if (!failStock) {
                        failStock = true;
                        Log.w(TAG, "Bar: trap-info object is not all public int, left as it is");
                    }
                    return info;
                }
                barField = f;
            }
            int stock = f.getInt(info);
            Object[] w = stock(cluster, true, new Object[] { info }, stock);
            return w == null ? info : w[0];
        } catch (Throwable t) {
            fail(t);
            return info;
        }
    }

    /** right after the stock call: a call that reached the cluster later than a frame sent again is put right */
    public static void after() {
        try {
            Integer b = SENT.get();
            if (b == null) return;
            SENT.remove();
            boolean differ;
            synchronized (NAVI) {
                differ = b != NAVI.current();
            }
            if (differ) postSend(Bar.MIN_GAP_MS);
        } catch (Throwable t) {
            // nothing
        }
    }

    // ------------------------------------------------------------------------------------------------ stock calls
    /**
     * a stock trap-info call. Returns the arguments to call with (a copy with the phone's bar), or null for as they
     * are. The last call is remembered for sending again.
     */
    private static Object[] stock(Object cluster, boolean asNew, Object[] args, int stockBar) throws Exception {
        SENT.remove();
        Slot slot = asNew ? SLOT_NEW : SLOT_INT;
        Method m = method(cluster, asNew);
        Object[] copy = asNew ? new Object[] { Bar.copy(args[0]) } : args.clone();
        if (stockBar < 0 || stockBar > Bar.MAX) {
            // a bar outside 0..100: remembered as the latest stock call, the bar is left alone
            synchronized (NAVI) {
                slot.target = cluster;
                slot.method = m;
                slot.args = copy;
                seq++;
            }
            return null;
        }
        boolean need;
        synchronized (NAVI) {
            need = NAVI.hasPhoneBar();
        }
        boolean phone = need && phoneGuiding();
        int b;
        boolean was, now;
        synchronized (NAVI) {
            slot.target = cluster;
            slot.method = m;
            slot.args = copy;
            seq++;
            was = NAVI.isOverriding();
            b = NAVI.onStock(stockBar, phone, SystemClock.elapsedRealtime());
            now = NAVI.isOverriding();
        }
        SENT.set(b);
        if (was && !now) log("revert: stock trap frame bar stays " + stockBar + " (phone not guiding)");
        if (!now) ovBar = -1;
        if (b == stockBar) return null;
        if (ovBar != b || ovStock != stockBar) {
            ovBar = b;
            ovStock = stockBar;
            log("override: stock trap frame bar " + stockBar + " -> " + b);
        }
        return Bar.withBar(args, asNew, barField, b);
    }

    private static Method method(Object cluster, boolean asNew) throws Exception {
        Class<?> k = cluster.getClass();
        if (!asNew) {
            Class<?>[] t = new Class<?>[Bar.INT_ARGS];
            for (int i = 0; i < t.length; i++) t[i] = int.class;
            return k.getMethod("updateTBTTrapInfo", t);
        }
        for (Method x : k.getMethods()) {
            if ("updateTBTTrapInfoNew".equals(x.getName()) && x.getParameterTypes().length == 1) return x;
        }
        throw new NoSuchMethodException("updateTBTTrapInfoNew");
    }

    // ------------------------------------------------------------------------------------------------ the phone
    /** the phone's bar (broadcast, on this class's thread) */
    static void onBar(int bar) {
        boolean phone = bar != Bar.NONE && phoneGuiding();
        Integer r;
        synchronized (NAVI) {
            r = NAVI.onBar(bar, phone, SystemClock.elapsedRealtime());
        }
        log("phone bar " + (bar == Bar.NONE ? "none" : String.valueOf(bar)) + (phone ? " (phone guiding)" : "") + (r != null ? ", frame sent again with " + r : ""));
        Handler h = handler;
        if (h != null) {
            h.removeCallbacks(EXPIRE);
            if (bar != Bar.NONE) h.postDelayed(EXPIRE, Bar.EXPIRE_MS + 500);
        }
        if (r != null) send();
    }

    private static final Runnable EXPIRE = new Runnable() {
        @Override
        public void run() {
            Integer r;
            boolean phone = phoneGuiding();
            synchronized (NAVI) {
                r = NAVI.check(phone, SystemClock.elapsedRealtime());
            }
            if (r != null) {
                log("phone bar expired or phone not guiding: stock bar goes back");
                send();
            }
        }
    };

    private static final Runnable SEND = new Runnable() {
        @Override
        public void run() {
            synchronized (NAVI) {
                sendPosted = false;
            }
            send();
        }
    };

    private static void postSend(long delay) {
        Handler h = handler;
        if (h == null) return;
        synchronized (NAVI) {
            if (sendPosted) return;
            sendPosted = true;
        }
        h.postDelayed(SEND, delay);
    }

    /** the remembered stock calls, sent again with the bar now decided (this class's thread only) */
    private static void send() {
        Object[] t = new Object[2];
        Method[] m = new Method[2];
        Object[][] a = new Object[2][];
        long s;
        int bar;
        synchronized (NAVI) {
            if (SLOT_INT.method == null && SLOT_NEW.method == null) return;
            long wait = lastSendAt + Bar.MIN_GAP_MS - SystemClock.elapsedRealtime();
            if (wait > 0) {
                Handler h = handler;
                if (!sendPosted && h != null) {
                    sendPosted = true;
                    h.postDelayed(SEND, wait);
                }
                return;
            }
            s = seq;
            bar = NAVI.current();
            Slot[] slots = { SLOT_INT, SLOT_NEW };
            for (int k = 0; k < 2; k++) {
                Slot sl = slots[k];
                if (sl.method == null || sl.args == null) continue;
                try {
                    a[k] = Bar.withBar(sl.args, k == 1, barField, bar);
                    t[k] = sl.target;
                    m[k] = sl.method;
                } catch (Throwable e) {
                    failSend(e);
                }
            }
            lastSendAt = SystemClock.elapsedRealtime();
        }
        for (int k = 0; k < 2; k++) {
            if (m[k] == null) continue;
            try {
                m[k].invoke(t[k], a[k]);
                log("trap frame sent again with bar " + bar);
            } catch (Throwable e) {
                failSend(e);
            }
        }
        boolean again;
        synchronized (NAVI) {
            again = seq != s;
        }
        if (again) postSend(Bar.MIN_GAP_MS);
    }

    // ------------------------------------------------------------------------------------------------ Android glue
    /** the receiver, once, on its own thread; tried again at most every 10 s when it fails */
    private static void register() {
        if (registered) return;
        long now = SystemClock.elapsedRealtime();
        synchronized (NAVI) {
            if (registered || now - registerTry < 10000L) return;
            registerTry = now;
        }
        try {
            Context c = BarOut.app();
            if (c == null) return;
            HandlerThread th = new HandlerThread("JMKBar");
            th.start();
            Handler h = new Handler(th.getLooper());
            c.registerReceiver(new BroadcastReceiver() {
                @Override
                public void onReceive(Context ctx, Intent i) {
                    try {
                        onBar(i.getIntExtra(Bar.EXTRA_BAR, Bar.NONE));
                    } catch (Throwable t) {
                        fail(t);
                    }
                }
            }, new IntentFilter(Bar.ACTION), null, h);
            synchronized (NAVI) {
                handler = h;
                registered = true;
            }
            Log.i(TAG, "Bar: navigation side ready (receiver " + Bar.ACTION + ")");
        } catch (Throwable t) {
            Log.w(TAG, "Bar: receiver not registered: " + t);
        }
    }

    /** is a phone guiding: Android Auto (GpmManager.isGpmNaviGuidance) or CarPlay (DiPOManager.isDiPOTurnByTurnMode) */
    static boolean phoneGuiding() {
        Context c = BarOut.app();
        if (c == null) return false;
        try {
            Object gpm = Class.forName("com.hkmc.gpm.GpmManager").getConstructor(Context.class).newInstance(c);
            if (Boolean.TRUE.equals(gpm.getClass().getMethod("isGpmNaviGuidance").invoke(gpm))) return true;
        } catch (Throwable t) {
            // not an Android Auto car or no answer
        }
        try {
            Object dipo = c.getSystemService("dipo");
            return dipo != null && Boolean.TRUE.equals(dipo.getClass().getMethod("isDiPOTurnByTurnMode").invoke(dipo));
        } catch (Throwable t) {
            return false;
        }
    }

    private static synchronized void log(String s) {
        long now = SystemClock.elapsedRealtime();
        if (now - logWindow >= LOG_WINDOW_MS) {
            logWindow = now;
            logs = 0;
        }
        if (logs >= LOGS_MAX) return;
        logs++;
        Log.i(TAG, "Bar: " + s);
    }

    private static void failSend(Throwable e) {
        if (failSend) return;
        failSend = true;
        Log.w(TAG, "Bar: trap frame not sent again: " + e);
    }

    private static void fail(Throwable t) {
        if (failStock) return;
        failStock = true;
        Log.w(TAG, "Bar: stock trap frame not handled: " + t);
    }
}
