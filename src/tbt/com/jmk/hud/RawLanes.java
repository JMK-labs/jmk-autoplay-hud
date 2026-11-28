package com.jmk.hud;

import android.util.Log;

import com.tcc.iap2.Iap2NotiMsg;

/**
 * jmk-autoplay-hud 0.3.3 (AGPL-3.0, as this package; JMK's own code, after the field list of hmg-seogaemo
 * (github.com/seogaemo/hmg-seogaemo, commit fbaacf7, CpLaneDecoder.java.src and .agents/carplay-tbt-external/iap2-protocol.md, AGPL-3.0): ported, adapted).
 * CarPlay lane guidance (iAP2 message 0x5204) arrives from the patched libiap2session as raw blobs: one blob per lane (param 2, repeated), each a run of
 * sub-parameters "<length BE16, includes these 4 bytes> <id BE16> <value>": 0 LaneIndex u16, 1 LaneStatus u8 (0 not good, 1 good, 2 preferred),
 * 2 LaneAngle i16 (repeated: 0 straight, negative left, positive right), 3 LaneAngleHighlight i16 (1000 = none). Other ids are ignored.
 * decode() reads the blobs of one message; the lane frame is then built by the head unit's own code (the same path as the structured items).
 * Nothing here throws: a blob that does not parse gives one log line and no lanes (-1); the caller sends nothing.
 * Log (JMKHUD): "cp lanes: raw n=<top-level items> items=<lane blobs> lanes=<decoded> layout=<a|b|ab|-> sent" or "... bad <why>"; once per session, before anything is decoded,
 * "cp lanes: raw first n=<top-level items> <id>:<type>:<len>:<hex> ..." (the bytes of params 0, 1 and 2, 256 bytes at most; param 3, the description text, only as id:type:len).
 * layout a = the blob is the param's value (the parser skips the TLV header: iAP2SessionPacketGetParam returns TLV+4); layout b = the value with its own 4-byte header in front.
 */
public final class RawLanes {
    private static final String TAG = "JMKHUD";
    private static final int MAX = 8;
    private static final int RAW = 0x0b;
    private static final int HEX_MAX = 256;
    private static boolean la, lb;

    private static final int[] STATUS = new int[MAX];
    private static final int[][] ANGLES = new int[MAX][];
    private static final int[][] HL = new int[MAX][];

    private RawLanes() { }

    /** The lanes of one 0x5204 message: their number (0 = none in it), or -1 when it must not be used. */
    public static synchronized int decode(Object msg) {
        int top = 0, items = 0, lanes = 0;
        String bad = null;
        la = false; lb = false;
        try {
            Iap2NotiMsg.Iap2ObjGroup g = msg == null ? null : ((Iap2NotiMsg) msg).getItemGroup();
            if (g == null) {
                bad = "no params";
            } else {
                top = g.getItemCnt();
                first(g, top);
                for (int i = 0; i < top && bad == null; i++) {
                    Iap2NotiMsg.Iap2ObjItem it = g.getObjItem(i);
                    if (it == null || it.getItemId() != 2) continue;
                    items++;
                    if (it.getItemParamType() != RAW) { bad = "param 2 is not raw (type " + it.getItemParamType() + ")"; break; }
                    if (lanes >= MAX) continue;
                    bad = lane(it.getItemByteArray(), lanes);
                    if (bad == null) lanes++;
                }
            }
        } catch (Throwable t) {
            bad = "error " + t.getClass().getName();
        }
        try {
            String lay = la && lb ? "ab" : la ? "a" : lb ? "b" : "-";
            if (bad != null) {
                Log.i(TAG, "cp lanes: raw n=" + top + " items=" + items + " lanes=" + lanes + " bad " + bad);
                Evt.raw(false, lay, code(bad));
                return -1;
            }
            Log.i(TAG, "cp lanes: raw n=" + top + " items=" + items + " lanes=" + lanes + " layout=" + lay + " sent");
            Evt.raw(true, lay, null);
        } catch (Throwable t) {
            // a log line is never worth a failure
        }
        return lanes;
    }

    /** A plain code for the counting line: noparams, notraw, short, tlv, exc. */
    private static String code(String bad) {
        if (bad.startsWith("no params")) return "noparams";
        if (bad.startsWith("param 2 is not raw")) return "notraw";
        if (bad.startsWith("lane blob short")) return "short";
        if (bad.startsWith("lane blob does not parse")) return "tlv";
        return "exc";
    }

    /** Once per session: the raw bytes of the first lane message, for settling the layout from one drive (nothing is decoded here). */
    private static void first(Iap2NotiMsg.Iap2ObjGroup g, int top) {
        try {
            if (!Evt.firstRaw()) return;
            StringBuilder s = new StringBuilder("cp lanes: raw first n=" + top);
            int left = HEX_MAX;
            for (int i = 0; i < top; i++) {
                Iap2NotiMsg.Iap2ObjItem it = g.getObjItem(i);
                if (it == null) continue;
                byte[] b = it.getItemByteArray();
                int id = it.getItemId();
                s.append(' ').append(id).append(':').append(it.getItemParamType()).append(':').append(b == null ? -1 : b.length);
                if (b != null && id <= 2 && left > 0) {
                    int n = Math.min(b.length, left);
                    s.append(':');
                    for (int k = 0; k < n; k++) { s.append(Character.forDigit((b[k] >> 4) & 15, 16)).append(Character.forDigit(b[k] & 15, 16)); }
                    left -= n;
                }
            }
            Log.i(TAG, s.toString());
        } catch (Throwable t) {
            // a log line is never worth a failure
        }
    }

    public static synchronized int status(int i) { return i >= 0 && i < MAX ? STATUS[i] : -1; }

    public static synchronized int[] angles(int i) { return i >= 0 && i < MAX ? ANGLES[i] : null; }

    public static synchronized int[] hl(int i) { return i >= 0 && i < MAX ? HL[i] : null; }

    /** One lane's blob into slot idx; null = fine, else why not. */
    static String lane(byte[] b, int idx) {
        if (b == null || b.length < 4) return "lane blob short";
        Object[] r = parse(b, 0);
        if (r != null) la = true;
        if (r == null && b.length >= 8 && u16(b, 0) == b.length && u16(b, 2) == 2) { r = parse(b, 4); if (r != null) lb = true; }   // the param's own header in front of its value
        if (r == null) return "lane blob does not parse (" + b.length + " bytes)";
        STATUS[idx] = (Integer) r[0];
        ANGLES[idx] = (int[]) r[1];
        HL[idx] = (int[]) r[2];
        return null;
    }

    /** {status, angles, highlights} of the sub-parameters from off to the end, or null when they do not tile the blob exactly. */
    private static Object[] parse(byte[] b, int off) {
        int status = -1, na = 0, nh = 0;
        int[] a = new int[16], h = new int[16];
        int p = off;
        while (p < b.length) {
            if (p + 4 > b.length) return null;
            int l = u16(b, p), id = u16(b, p + 2);
            if (l < 4 || p + l > b.length) return null;
            int vl = l - 4;
            if (id == 1) {
                if (vl == 1) status = b[p + 4] & 0xff;
                else if (vl == 2) status = u16(b, p + 4);
                else return null;
            } else if (id == 2) {
                if (vl != 2) return null;
                if (na < a.length) a[na++] = (short) u16(b, p + 4);
            } else if (id == 3) {
                if (vl != 2) return null;
                if (nh < h.length) h[nh++] = (short) u16(b, p + 4);
            }
            p += l;
        }
        if (p != b.length) return null;
        return new Object[] { status, na == 0 ? null : java.util.Arrays.copyOf(a, na), nh == 0 ? null : java.util.Arrays.copyOf(h, nh) };
    }

    private static int u16(byte[] b, int p) { return ((b[p] & 0xff) << 8) | (b[p + 1] & 0xff); }
}
