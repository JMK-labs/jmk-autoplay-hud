package com.jmk.hud;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

import android.util.Log;

/**
 * jmk-autoplay-hud 0.2.6 (AGPL-3.0, as this package; JMK's own code, after the cp_keepbt setting of Danpung 0.8.0-r6c, AGPL-3.0).
 * Wireless CarPlay keeps the phone's Bluetooth connected.
 * Every call is inside try / catch Throwable: a missing class or field, an unreadable value or any exception means the stock code runs.
 */
public final class BtKeep {
    private static final String TAG = "JMKHUD";
    private static final String SWITCH = "persist.leafia.cp.keepbt";
    private static final String BRIDGE = "com.ev6.cpwl.Bridge";

    private static volatile boolean endedWireless;

    private BtKeep() { }

    /** The stock call that tells the Bluetooth service CarPlay is connected: true = leave it out. */
    public static boolean keep(boolean connect) {
        try {
            boolean wireless = flag("sCpWireless");
            boolean usb = flag("sUsb");
            boolean on = switchOn();
            String why;
            boolean keep = false;
            if (!connect) why = "disconnect";
            else if (!wireless) why = usb ? "usb" : "not-wireless";
            else if (!on) why = "switch-off";
            else { keep = true; why = "wireless"; }
            Log.i(TAG, "BtKeep: connect=" + connect + " wireless=" + wireless + " usb=" + usb + " switch=" + (on ? "on" : "off")
                    + " after-wireless-end=" + endedWireless + " from=" + caller() + " -> " + (keep ? "kept" : "stock") + " (" + why + ")");
            return keep;
        } catch (Throwable t) {
            return false;
        }
    }

    /** A CarPlay session started (mode 1 = wireless). */
    public static void start(int mode) {
        try {
            if (mode != 1) endedWireless = false;
            Log.i(TAG, "BtKeep: session started mode=" + mode);
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    /** A CarPlay session ended (mode 1 = wireless). */
    public static void end(int mode) {
        try {
            if (mode == 1) endedWireless = true;
            Log.i(TAG, "BtKeep: session ended mode=" + mode);
        } catch (Throwable t) {
            // never worth a failure
        }
    }

    private static boolean flag(String name) throws Exception {
        Field f = Class.forName(BRIDGE).getDeclaredField(name);
        f.setAccessible(true);
        return f.getBoolean(null);
    }

    /** Off only for "0"; absent or anything else is on. A value that cannot be read gives an exception: the stock code runs. */
    private static boolean switchOn() throws Exception {
        Method m = Class.forName("android.os.SystemProperties").getMethod("get", String.class);
        Object v = m.invoke(null, SWITCH);
        return !"0".equals(v);
    }

    private static String caller() {
        StackTraceElement[] st = new Throwable().getStackTrace();
        for (int i = 0; i + 1 < st.length; i++) {
            if ("keep".equals(st[i].getMethodName()) && BtKeep.class.getName().equals(st[i].getClassName())) {
                // [i + 1] is the stock method that was asked (its own frame), [i + 2] the one that called it
                StackTraceElement c = i + 2 < st.length ? st[i + 2] : st[i + 1];
                String cn = c.getClassName();
                return cn.substring(cn.lastIndexOf('.') + 1) + "." + c.getMethodName();
            }
        }
        return "?";
    }
}
