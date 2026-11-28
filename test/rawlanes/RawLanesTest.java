package com.jmk.hud;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;

import com.tcc.iap2.Iap2NotiMsg;

/** RawLanes on the JVM, from the wire format of 0x5204 (iAP2 spec as Seogaemo's iap2-protocol.md): java com.jmk.hud.RawLanesTest */
public final class RawLanesTest {
    static int fails;
    static String log = "";

    static void check(String what, boolean ok) {
        if (!ok) { fails++; System.out.println("FAIL " + what); } else System.out.println("ok   " + what);
    }

    static byte[] tlv(int id, int... v) {
        byte[] b = new byte[4 + v.length];
        b[0] = (byte) ((b.length >> 8) & 255); b[1] = (byte) (b.length & 255); b[2] = (byte) (id >> 8); b[3] = (byte) id;
        for (int i = 0; i < v.length; i++) b[4 + i] = (byte) v[i];
        return b;
    }

    static byte[] i16(int id, int v) { return tlv(id, (v >> 8) & 255, v & 255); }

    static byte[] cat(byte[]... p) {
        int n = 0;
        for (byte[] x : p) n += x.length;
        byte[] r = new byte[n]; int o = 0;
        for (byte[] x : p) { System.arraycopy(x, 0, r, o, x.length); o += x.length; }
        return r;
    }

    static byte[] lane(int idx, int status, int[] angles, int hl) {
        byte[][] parts = new byte[angles.length + 3][];
        parts[0] = i16(0, idx);
        parts[1] = tlv(1, status);
        for (int i = 0; i < angles.length; i++) parts[2 + i] = i16(2, angles[i]);
        parts[2 + angles.length] = i16(3, hl);
        return cat(parts);
    }

    static Iap2NotiMsg msg(Object... items) {   // (id, type, byte[]) triples
        Iap2NotiMsg m = new Iap2NotiMsg();
        m.group = new Iap2NotiMsg.Iap2ObjGroup();
        for (int i = 0; i < items.length; i += 3) m.group.items.add(new Iap2NotiMsg.Iap2ObjItem((Integer) items[i], (Integer) items[i + 1], (byte[]) items[i + 2]));
        return m;
    }

    static int run(final Object m) {
        PrintStream old = System.err;
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        System.setErr(new PrintStream(b));
        int r;
        try { r = RawLanes.decode(m); } finally { System.setErr(old); }
        log = b.toString();
        return r;
    }

    static boolean arr(int[] a, int... e) { return java.util.Arrays.equals(a, e); }

    public static void main(String[] x) {
        // one lane: straight, good, highlight on straight (the spec's fields in order)
        int n = run(msg(0, 0xb, tlv(0, 0, 7), 1, 0xb, tlv(1, 0, 1), 2, 0xb, lane(0, 1, new int[] { 0 }, 0), 3, 0xb, "Use the left lane".getBytes()));
        check("one lane: 1 lane, 'sent' line with n items lanes layout=a", n == 1 && log.contains("cp lanes: raw n=4 items=1 lanes=1 layout=a sent"));
        check("the first message of the session: the raw bytes logged once (params 0-2 as hex, param 3 only as id:type:len)", log.contains("cp lanes: raw first n=4 0:11:6:000600000007 1:11:6:") && log.contains(" 3:11:17") && !log.contains("557365"));
        check("one lane: the counting line EVT cp-raw res=ok layout=a, seq and pid", log.contains("EVT cp-raw res=ok layout=a why=- seq=") && log.contains("pid=4242"));
        check("one lane: status 1, angles {0}, highlight {0}", RawLanes.status(0) == 1 && arr(RawLanes.angles(0), 0) && arr(RawLanes.hl(0), 0));
        n = run(msg(2, 0xb, lane(0, 1, new int[] { 0 }, 0)));
        check("the second message of the session: no 'first' line again", !log.contains("raw first"));
        Evt.sessionEnd();
        n = run(msg(2, 0xb, lane(0, 1, new int[] { 0 }, 0)));
        check("after the session end the next message logs its bytes again", log.contains("raw first"));
        // several lanes, repeated LaneAngles, a negative angle, highlight 1000 (none), status 2
        n = run(msg(2, 0xb, lane(0, 1, new int[] { -90, 0 }, -90), 2, 0xb, lane(1, 2, new int[] { 0, 90, 180 }, 90), 2, 0xb, lane(2, 0, new int[] { 90 }, 1000)));
        check("three lanes in order", n == 3 && RawLanes.status(0) == 1 && RawLanes.status(1) == 2 && RawLanes.status(2) == 0);
        check("repeated LaneAngles keep their order and sign", arr(RawLanes.angles(0), -90, 0) && arr(RawLanes.angles(1), 0, 90, 180) && arr(RawLanes.angles(2), 90));
        check("highlights: -90, 90, 1000", arr(RawLanes.hl(0), -90) && arr(RawLanes.hl(1), 90) && arr(RawLanes.hl(2), 1000));
        // a lane without angles / without status
        n = run(msg(2, 0xb, cat(i16(0, 3), i16(3, 1000))));
        check("a lane without angles and status: angles null, status -1, highlight kept", n == 1 && RawLanes.angles(0) == null && RawLanes.status(0) == -1 && arr(RawLanes.hl(0), 1000));
        // status as two bytes
        n = run(msg(2, 0xb, cat(tlv(1, 0, 2), i16(2, 0))));
        check("a two-byte status is read", n == 1 && RawLanes.status(0) == 2);
        // empty: no lane blob at all
        n = run(msg(0, 0xb, tlv(0, 0, 7), 1, 0xb, tlv(1, 0, 1)));
        check("empty message (no lanes): 0, one line, nothing to send but the clear", n == 0 && log.contains("items=0 lanes=0 layout=- sent"));
        n = run(msg());
        check("no params at all: 0 lanes", n == 0);
        // truncated blobs, bad lengths: -1 and one bad line
        byte[] ok = lane(0, 1, new int[] { 0, 90 }, 0);
        byte[] cut = java.util.Arrays.copyOf(ok, ok.length - 1);
        n = run(msg(2, 0xb, cut));
        check("truncated blob: -1, one 'bad' line and one counting line (bad / tlv)", n == -1 && log.contains("bad lane blob does not parse") && log.contains("EVT cp-raw res=bad layout=- why=tlv seq=") && log.split("\n").length == 2);
        n = run(msg(2, 0xb, new byte[] { 0, 6 }));
        check("blob shorter than a header: -1, counted as bad / short", n == -1 && log.contains("bad lane blob short") && log.contains("EVT cp-raw res=bad layout=- why=short seq="));
        n = run(msg(2, 0xb, null));
        check("a null blob: -1", n == -1);
        byte[] big = ok.clone(); big[1] = (byte) 200;
        n = run(msg(2, 0xb, big));
        check("a length that runs past the end: -1", n == -1);
        byte[] small = ok.clone(); small[0] = 0; small[1] = 3;
        n = run(msg(2, 0xb, small));
        check("a sub-parameter length below 4: -1", n == -1);
        n = run(msg(2, 0xb, cat(i16(0, 0), tlv(2, 1, 2, 3))));
        check("a LaneAngle that is not 2 bytes: -1", n == -1);
        n = run(msg(2, 0xb, cat(lane(0, 1, new int[] { 0 }, 0), new byte[] { 0, 0 })));
        check("trailing bytes that are no sub-parameter: -1", n == -1);
        // one bad lane among good ones: nothing is used (-1)
        n = run(msg(2, 0xb, lane(0, 1, new int[] { 0 }, 0), 2, 0xb, cut));
        check("one bad lane among good ones: -1, nothing used", n == -1);
        // unknown ids are ignored
        n = run(msg(2, 0xb, cat(lane(0, 1, new int[] { 90 }, 90), tlv(9, 1, 2, 3, 4))));
        check("an unknown sub-parameter is ignored", n == 1 && arr(RawLanes.angles(0), 90));
        // the param's own header in front of the value
        byte[] inner = lane(0, 1, new int[] { 0, -90 }, -90);
        byte[] wrapped = cat(tlv(2, new int[0]), inner);
        wrapped[0] = (byte) ((wrapped.length >> 8) & 255); wrapped[1] = (byte) (wrapped.length & 255);
        n = run(msg(2, 0xb, wrapped));
        check("the value with the param's own 4-byte header in front is read too, layout=b", n == 1 && arr(RawLanes.angles(0), 0, -90) && log.contains("layout=b"));
        n = run(msg(2, 0xb, wrapped, 2, 0xb, inner));
        check("both layouts in one message are logged as layout=ab", n == 2 && log.contains("layout=ab"));
        byte[] bigb = new byte[300]; java.util.Arrays.fill(bigb, (byte) 0xAB);
        Evt.sessionEnd();
        run(msg(2, 0xb, bigb));
        String fl = log.substring(log.indexOf("raw first"));
        String hx = fl.substring(fl.indexOf("2:11:300:") + 9).split("\n")[0].trim();
        check("the hex of the first message is cut at 256 bytes (512 hex digits)", fl.indexOf("2:11:300:") >= 0 && hx.length() == 512);
        // the structured type (not raw) is not ours: -1 with the reason
        n = run(msg(2, 0xd, new byte[0]));
        check("a group item (type 0xd) is not decoded here: -1, counted as bad / notraw", n == -1 && log.contains("not raw") && log.contains("why=notraw"));
        // more than 8 lanes: the first 8 only
        Object[] nine = new Object[27];
        for (int i = 0; i < 9; i++) { nine[3 * i] = 2; nine[3 * i + 1] = 0xb; nine[3 * i + 2] = lane(i, 1, new int[] { i * 10 }, 0); }
        n = run(msg(nine));
        check("nine lanes: eight kept", n == 8 && arr(RawLanes.angles(7), 70) && log.contains("items=9 lanes=8"));
        // the bad values do not leak: after a bad message the slots are not reported as lanes
        run(msg(2, 0xb, cut));
        check("after -1 the log line says bad and the caller sends nothing (count is -1)", log.contains("bad"));
        // null message, wrong class, a throwing accessor: never an exception
        check("null message: -1, counted as bad / noparams", run(null) == -1 && log.contains("why=noparams"));
        check("not a message: -1, the class is named", run("x") == -1 && log.contains("bad error java.lang.ClassCastException"));
        Iap2NotiMsg.boom = true;
        int rb = run(msg(2, 0xb, ok));
        Iap2NotiMsg.boom = false;
        check("an accessor that throws: -1 with the exception class, no exception out, counted as bad / exc", rb == -1 && log.contains("error java.lang.IllegalStateException") && log.contains("why=exc"));
        check("out of range accessors are safe", RawLanes.status(-1) == -1 && RawLanes.angles(99) == null && RawLanes.hl(8) == null);
        System.out.println(fails == 0 ? "rawlanes: passed" : "rawlanes: FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
