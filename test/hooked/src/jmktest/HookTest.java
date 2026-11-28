package jmktest;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

import com.hkmc.cluster.NavigationCluster;
import com.tcc.iap2.Iap2NotiMsg;

/**
 * Runs the HOOKED u.applyLanes of a DiPO result dex (the real classes: u, LeafiaLane, Lanes, RawLanes) with doubles for the iAP2 message and the cluster service.
 * Output: one "FRAMES <n>" line, then one "FRAME <hex>" line per frame the cluster was given, then "THROW <class>" if applyLanes threw.
 *   dalvikvm -cp <result dex jar>:<test jar> jmktest.HookTest <scenario>
 */
public final class HookTest {
    static byte[] tlv(int id, int... v) {
        byte[] b = new byte[4 + v.length];
        b[0] = (byte) ((b.length >> 8) & 255); b[1] = (byte) (b.length & 255); b[2] = (byte) (id >> 8); b[3] = (byte) id;
        for (int i = 0; i < v.length; i++) b[4 + i] = (byte) v[i];
        return b;
    }
    static byte[] i16(int id, int v) { return tlv(id, (v >> 8) & 255, v & 255); }
    static byte[] cat(byte[]... p) {
        int n = 0; for (byte[] x : p) n += x.length;
        byte[] r = new byte[n]; int o = 0;
        for (byte[] x : p) { System.arraycopy(x, 0, r, o, x.length); o += x.length; }
        return r;
    }
    static byte[] blob(int idx, int status, int[] angles, int hl) {
        byte[][] parts = new byte[angles.length + 3][];
        parts[0] = i16(0, idx); parts[1] = tlv(1, status);
        for (int i = 0; i < angles.length; i++) parts[2 + i] = i16(2, angles[i]);
        parts[2 + angles.length] = i16(3, hl);
        return cat(parts);
    }

    /** one lane = {status, hl, angles...} */
    static final int[][] LANES_A = { { 1, 0, 0 }, { 1, 90, -90, 90 }, { 0, 1000, 90 } };
    static final int[][] LANES_B = { { 2, -90, 0, -90 }, { 1, 0, 0, 90 } };

    static Iap2NotiMsg structured(int[][] lanes) {
        Iap2NotiMsg m = new Iap2NotiMsg(); m.group = new Iap2NotiMsg.Iap2ObjGroup();
        Iap2NotiMsg.Iap2ObjItem i0 = new Iap2NotiMsg.Iap2ObjItem(0, 5); i0.ints = new int[] { 7 }; m.group.items.add(i0);
        Iap2NotiMsg.Iap2ObjItem i2 = new Iap2NotiMsg.Iap2ObjItem(2, 0xd);
        i2.groups = new Iap2NotiMsg.Iap2ObjGroup[lanes.length];
        for (int k = 0; k < lanes.length; k++) {
            Iap2NotiMsg.Iap2ObjGroup g = new Iap2NotiMsg.Iap2ObjGroup();
            Iap2NotiMsg.Iap2ObjItem a = new Iap2NotiMsg.Iap2ObjItem(0, 5); a.ints = new int[] { k }; g.items.add(a);
            Iap2NotiMsg.Iap2ObjItem s = new Iap2NotiMsg.Iap2ObjItem(1, 8); s.ints = new int[] { lanes[k][0] }; g.items.add(s);
            int[] ang = new int[lanes[k].length - 2]; System.arraycopy(lanes[k], 2, ang, 0, ang.length);
            if (ang.length > 0) { Iap2NotiMsg.Iap2ObjItem an = new Iap2NotiMsg.Iap2ObjItem(2, 5); an.ints = ang; g.items.add(an); }
            Iap2NotiMsg.Iap2ObjItem h = new Iap2NotiMsg.Iap2ObjItem(3, 5); h.ints = new int[] { lanes[k][1] }; g.items.add(h);
            i2.groups[k] = g;
        }
        m.group.items.add(i2);
        return m;
    }

    static Iap2NotiMsg raw(int[][] lanes, boolean cutLast, boolean withHeader) {
        Iap2NotiMsg m = new Iap2NotiMsg(); m.group = new Iap2NotiMsg.Iap2ObjGroup();
        Iap2NotiMsg.Iap2ObjItem i0 = new Iap2NotiMsg.Iap2ObjItem(0, 0xb); i0.bytes = tlv(0, 0, 7).length > 4 ? new byte[] { 0, 7 } : null; m.group.items.add(i0);
        for (int k = 0; k < lanes.length; k++) {
            int[] ang = new int[lanes[k].length - 2]; System.arraycopy(lanes[k], 2, ang, 0, ang.length);
            byte[] b = blob(k, lanes[k][0], ang, lanes[k][1]);
            if (withHeader) { byte[] h = tlv(2, new int[0]); b = cat(h, b); b[0] = (byte) ((b.length >> 8) & 255); b[1] = (byte) (b.length & 255); }
            if (cutLast && k == lanes.length - 1) b = java.util.Arrays.copyOf(b, b.length - 1);
            Iap2NotiMsg.Iap2ObjItem it = new Iap2NotiMsg.Iap2ObjItem(2, 0xb); it.bytes = b; m.group.items.add(it);
        }
        return m;
    }

    static String hex(byte[] b) { StringBuilder s = new StringBuilder(); for (byte x : b) s.append(String.format("%02x", x & 255)); return s.toString(); }

    public static void main(String[] a) throws Exception {
        String sc = a[0];
        Iap2NotiMsg m;
        if (sc.equals("structA")) m = structured(LANES_A);
        else if (sc.equals("rawA")) m = raw(LANES_A, false, false);
        else if (sc.equals("rawAhdr")) m = raw(LANES_A, false, true);
        else if (sc.equals("structB")) m = structured(LANES_B);
        else if (sc.equals("rawB")) m = raw(LANES_B, false, false);
        else if (sc.equals("rawBad")) m = raw(LANES_A, true, false);
        else if (sc.equals("structEmpty")) { m = new Iap2NotiMsg(); m.group = new Iap2NotiMsg.Iap2ObjGroup(); }
        else if (sc.equals("rawEmpty")) { m = new Iap2NotiMsg(); m.group = new Iap2NotiMsg.Iap2ObjGroup(); Iap2NotiMsg.Iap2ObjItem i0 = new Iap2NotiMsg.Iap2ObjItem(0, 0xb); i0.bytes = new byte[] { 0, 7 }; m.group.items.add(i0); }
        else if (sc.equals("nullCp")) m = raw(LANES_A, false, false);       // run with the fake LeafiaLane first on the class path (cpLane returns null)
        else if (sc.equals("throwCp")) { Class.forName("com.leafia.kr.LeafiaLane").getField("THROW").setBoolean(null, true); m = raw(LANES_A, false, false); }   // ... and throws
        else throw new IllegalArgumentException(sc);
        Class<?> u = Class.forName("com.daudio.app.dipo.e.u");
        Object nav = u.getConstructor(android.content.Context.class).newInstance(new Object[] { null });
        Field ak = u.getDeclaredField("Ak"); ak.setAccessible(true);
        ak.set(nav, new NavigationCluster(null));
        Method apply = u.getMethod("applyLanes", Object.class);
        try {
            apply.invoke(null, m);
        } catch (java.lang.reflect.InvocationTargetException e) {
            System.out.println("THROW " + e.getCause().getClass().getName());
        }
        System.out.println("FRAMES " + NavigationCluster.FRAMES.size());
        for (byte[] f : NavigationCluster.FRAMES) System.out.println("FRAME " + hex(f));
    }
}
