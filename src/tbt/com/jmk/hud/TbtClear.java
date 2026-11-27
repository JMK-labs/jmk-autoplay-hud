package com.jmk.hud;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.util.Log;

import com.hkmc.cluster.NavigationCluster;

/**
 * jmk-autoplay-hud 0.1.19 (AGPL-3.0, as this package): "계기판 길안내 지우기" in the patched HKMC_GPM (Android Auto)
 * and HKMC_DiPO (CarPlay).
 *
 * The app's service registers one receiver at its onCreate (GPM: GalReceiverService, DiPO: DipoService; no manifest
 * change), for the broadcast com.jmk.hud.TBT_CLEAR, which only root / system / shell can send (the sender must hold
 * WRITE_SECURE_SETTINGS; uid 0 and system always pass):
 *
 *     am broadcast -a com.jmk.hud.TBT_CLEAR
 *
 * It runs the app's own guidance release on the app's live turn-by-turn owner, through the owner class's
 * public static boolean jmkClear(Context) (tbt-clear-gpm.diff / tbt-clear-dipo.diff):
 *   GPM   GpmNaviTBTManager.jmkClear: releaseGuidance() of the manager that last drew on the cluster
 *         (destination name "", TBT_INFO DisplayType 8, sub info cleared, HUD extras and turn list blank)
 *   DiPO  u.jmkClear: release() below + sendHudBlank() of the route guidance analyzer
 * When the app has no such owner (no session drew since the process started), the same calls go to a new
 * NavigationCluster directly (send()). Guidance still running on the phone draws again with its next update.
 */
public final class TbtClear extends BroadcastReceiver {
    public static final String ACTION = "com.jmk.hud.TBT_CLEAR";
    private static final String TAG = "JMKHUD";
    private static TbtClear sOne;
    private final Class<?> mOwner;

    private TbtClear(Class<?> owner) {
        mOwner = owner;
    }

    /** From the service's onCreate; once per process, on the application context (outlives the service). */
    public static void register(Context context, Class<?> owner) {
        try {
            synchronized (TbtClear.class) {
                if (context == null || sOne != null) {
                    return;
                }
                Context app = context.getApplicationContext();
                if (app == null) {
                    app = context;
                }
                TbtClear r = new TbtClear(owner);
                app.registerReceiver(r, new IntentFilter(ACTION), "android.permission.WRITE_SECURE_SETTINGS", null);
                sOne = r;
            }
        } catch (Throwable t) {
            Log.w(TAG, "TBT_CLEAR receiver not registered: " + t);
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        boolean live = false;
        try {
            Object r = mOwner.getMethod("jmkClear", Context.class).invoke(null, context);
            live = Boolean.TRUE.equals(r);
        } catch (Throwable t) {
            Log.w(TAG, "TBT_CLEAR: " + mOwner.getName() + ".jmkClear: " + t);
        }
        if (!live) {
            try {
                send(new NavigationCluster(context));
            } catch (Throwable t) {
                Log.w(TAG, "TBT_CLEAR: cluster: " + t);
                return;
            }
        }
        Log.i(TAG, "TBT_CLEAR: turn-by-turn cleared (" + (live ? "live owner" : "cluster") + ")");
    }

    /** GPM's releaseGuidance cluster calls (the stock release, DisplayType 8 since 0.1.5). */
    public static void release(NavigationCluster n) {
        NavigationCluster.DestinationName d = new NavigationCluster.DestinationName();
        d.type = 0;
        d.name = "";
        n.updateTPFlexibleDestinationName(d);
        n.updateTBTInfo(8, 0, 0f, 0f, -1, 0, 0, 0, -1);
        n.updateTBTSubInfo(0f, -1, 0, 0, 0, 0, 0, 0f, -1, 0);
    }

    /** release() plus the HUD extras (lanes) and the turn list blank, as sendHudBlank sends them. */
    static void send(NavigationCluster n) {
        release(n);
        n.updateTBTSubInfo2C(0, 0, 0, 0, 0, 0, 0, 0, 0);
        byte[] lanes = new byte[81];
        lanes[0] = (byte) 0xf1;
        n.updateLaneInfo(lanes);
        byte[] list = new byte[2];
        list[0] = (byte) 0xf2;
        n.updateTPTurnListNew(list);
        n.updateTPTurnListNew(list);
    }
}
