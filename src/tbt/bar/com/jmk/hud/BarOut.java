package com.jmk.hud;

import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;
import android.util.Log;

/**
 * jmk-autoplay-hud 0.1.33 (AGPL-3.0, as this package): the phone processes' side of the cluster distance bar (HKMC_GPM
 * and HKMC_DiPO). The turn frame these builds send already carries the bar; this tells the same value to the
 * navigation process (NaviBar) by broadcast com.jmk.hud.BAR, when it changes and every Bar.RESEND_MS while a bar is
 * shown, and Bar.NONE when guidance ends. The hooks (bar.py):
 *
 *   GpmNaviTBTManager.updateTBTInfo   BarOut.aa(LeafiaTurn.standard's result, null when it gave none)
 *   GpmNaviTBTManager.releaseGuidance BarOut.end()
 *   DiPO u.a (the one updateTBTInfo send of the route guidance update)   BarOut.cp(display type, bar)
 *   DiPO u.jmkRelease                 BarOut.end()
 *
 * Log (tag JMKHUD): one line per broadcast sent. Nothing here ever throws into the stock code.
 *
 * Ported from an AGPL-3.0 Korean-firmware mod code base (phone bar, 2.4.5 generation), AGPL-3.0:
 * the phone-bar send and the bar output, and the places the turn frame's bar is sent from
 * (NONE when guidance ends). Ported, adapted: our own
 * action name, no HMG-API; the decision is Bar.Sender.
 */
public final class BarOut {
    private static final String TAG = "JMKHUD";
    private static final Bar.Sender SENDER = new Bar.Sender();

    private BarOut() {
    }

    /** Android Auto: the result of LeafiaTurn.standard (null: none) of the turn frame being sent */
    public static void aa(int[] result) {
        send(Bar.aaBar(result), "aa");
    }

    /** CarPlay: the display type and bar of the turn frame being sent */
    public static void cp(int display, int bar) {
        send(Bar.cpBar(display, bar), "cp");
    }

    /** guidance ended or was released */
    public static void end() {
        send(Bar.NONE, "end");
    }

    private static java.lang.reflect.Method current;

    private static synchronized void send(int bar, String who) {
        try {
            Context c = app();
            if (c == null) return;
            if (!SENDER.due(bar, SystemClock.elapsedRealtime())) return;
            Intent i = new Intent(Bar.ACTION);
            i.addFlags(Intent.FLAG_RECEIVER_FOREGROUND);
            i.putExtra(Bar.EXTRA_BAR, bar);
            c.sendBroadcast(i);
            Log.i(TAG, "Bar: " + who + " broadcast bar " + (bar == Bar.NONE ? "none" : String.valueOf(bar)));
        } catch (Throwable t) {
            // the turn frame goes on
        }
    }

    /** this process's Application (ActivityThread.currentApplication, on every Android since 1.x) */
    static synchronized Context app() {
        try {
            if (current == null) current = Class.forName("android.app.ActivityThread").getMethod("currentApplication");
            Object a = current.invoke(null);
            return a instanceof Context ? (Context) a : null;
        } catch (Throwable t) {
            return null;
        }
    }
}
