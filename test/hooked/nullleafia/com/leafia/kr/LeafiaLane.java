package com.leafia.kr;

/** A LeafiaLane whose cpLane gives null (the hook must not trip over it): shadows the real class when it comes first on the class path. */
public class LeafiaLane {
    public static void cp(byte[] f, int[] a, int[] b, int[] c, int[] d) { }
    public static byte[] cpGate(Object cluster, byte[] f) { return f; }
    public static boolean THROW;
    public static int[] cpLane(int[] a, int[] b, int[] c, int d) { if (THROW) throw new IllegalStateException("boom"); return null; }
    public static void capture(String a, String b, int c, byte[] d, byte[] e, String f) { }
    public static int mode() { return 1; }
    public static int icon(int a) { return 0; }
    public static boolean cpClearBegin(Object o) { return true; }
}
