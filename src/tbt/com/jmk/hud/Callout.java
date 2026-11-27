package com.jmk.hud;

import android.os.SystemClock;
import android.util.Log;

import jmkhud.link.Clock;
import jmkhud.link.HookClient;
import jmkhud.link.android.LocalSockets;

/**
 * jmk-autoplay-hud (AGPL-3.0, as this package; JMK's own code). HUD DiPO bridge: at the point where Leafia starts the car hotspot it
 * asks a local JMK service (`jmk.core`) first and skips its own start when the service answers that it should (the hotspot is already
 * on or being started, or the car's settings keep it off) — readable in the public HUD source.
 */
public final class Callout {
    private static final String TAG = "JMKHUD";
    private static final String NAME = "jmk.core";
    private static final String ROLE = "hud-dipo";
    private static final String VER = "0.2.1";
    private static final int WAIT_MS = 300;

    private Callout() { }

    public static int ask() {
        try {
            HookClient.Answer a = client().hotspotOn(WAIT_MS);
            if (a.hold) return 1;
            return "timeout".equals(a.how) ? 2 : 0;
        } catch (Throwable t) {
            return 0;
        }
    }

    private static HookClient client() {
        return HookClient.get(LocalSockets.connector(NAME), new Clock() {
            public long el() { return SystemClock.elapsedRealtime(); }
        }, new jmkhud.link.Log() {
            public void line(String s) { Log.i(TAG, s); }
        }, ROLE, VER);
    }
}
