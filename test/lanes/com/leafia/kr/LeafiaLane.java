package com.leafia.kr;

/** jmk-autoplay-hud 0.1.29 test double of Leafia's lane log call (public static, the signature Lanes uses): it records the call. */
public final class LeafiaLane {
    public static int calls;
    public static String tag, caller, note;
    public static int mode;
    public static byte[] before, after;
    public static boolean fail;

    private LeafiaLane() {
    }

    public static void capture(String t, String c, int m, byte[] b, byte[] a, String n) {
        if (fail) {
            throw new IllegalStateException("log failed");
        }
        calls++;
        tag = t;
        caller = c;
        mode = m;
        before = b;
        after = a;
        note = n;
    }
}
