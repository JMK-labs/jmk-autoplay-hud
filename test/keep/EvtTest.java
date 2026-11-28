package com.jmk.hud;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;

/** Evt on the JVM: java com.jmk.hud.EvtTest (one JVM, the cases in order). */
public final class EvtTest {
    static int fails;

    static void check(String what, boolean ok) {
        if (!ok) { fails++; System.out.println("FAIL " + what); } else System.out.println("ok   " + what);
    }

    static String err(Runnable r) {
        PrintStream old = System.err;
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        System.setErr(new PrintStream(b));
        try { r.run(); } finally { System.setErr(old); }
        return b.toString();
    }

    static byte[] msg(int id) {   // 0x40 0x40, length 6 + 2, id, two bytes of a parameter
        return new byte[] { 0x40, 0x40, 0, 8, (byte) (id >> 8), (byte) id, 0, 0 };
    }

    public static void main(String[] a) {
        check("token: plain letters, lower case, spaces to dash", Evt.token("Apple Maps").equals("apple-maps"));
        check("token: Korean text becomes x + eight hex digits, never the text", Evt.token("네이버 지도").matches("x[0-9a-f]{8}") && Evt.token("네이버 지도").equals(Evt.token("네이버 지도")));
        check("token: empty or null is ?", Evt.token("").equals("?") && Evt.token(null).equals("?"));
        check("token: cut at 24", Evt.token("abcdefghijklmnopqrstuvwxyz0123").length() == 24);
        Evt.source("Apple Maps");
        String o = err(new Runnable() { public void run() { Evt.iapIn(msg(0x5204), 8); } });
        check("first lane message: one line, n=1 app=apple-maps proj=cp, seq and pid", o.contains("EVT cp-lanes n=1 app=apple-maps proj=cp") && o.contains("pid=4242"));
        o = err(new Runnable() { public void run() { Evt.iapIn(msg(0x5204), 8); Evt.iapIn(msg(0x5204), 8); } });
        check("more lane messages: no line", !o.contains("EVT"));
        o = err(new Runnable() { public void run() { Evt.iapIn(msg(0x5202), 8); Evt.iapIn(new byte[] { 1, 2, 3 }, 3); Evt.iapIn(null, 5); } });
        check("other messages, a short buffer and null: no line, no exception", !o.contains("EVT"));
        byte[] two = new byte[16];
        System.arraycopy(msg(0x5204), 0, two, 0, 8); System.arraycopy(msg(0x5204), 0, two, 8, 8);
        o = err(new Runnable() { public void run() { Evt.sessionEnd(); } });
        check("session end: the rest (2 after the first) once", o.contains("EVT cp-lanes n=2 ") );
        o = err(new Runnable() { public void run() { Evt.sessionEnd(); } });
        check("session end again: nothing", !o.contains("EVT"));
        final byte[] t = two;
        o = err(new Runnable() { public void run() { Evt.iapIn(t, 16); } });
        check("a buffer with two messages: the first line carries n=2", o.contains("EVT cp-lanes n=2 "));
        check("a bad length (0) is not counted", err(new Runnable() { public void run() { Evt.sessionEnd(); byte[] z = msg(0x5204); z[3] = 2; Evt.iapIn(z, 8); } }).equals(""));
        o = err(new Runnable() { public void run() { Evt.restart(new Object() { public void leafiaRestartRouteGuidance() { } }); } });
        check("restart: a line for start and done", o.contains("source restart start") && o.contains("source restart done"));
        o = err(new Runnable() { public void run() { Evt.restart(new Object()); } });
        check("restart without the method: a failed line, no exception", o.contains("source restart failed"));
        o = err(new Runnable() { public void run() { Evt.end("phone-stop", "aa", null); } });
        check("end: why proj, no trig for a named cause", o.contains("EVT tbt-end why=phone-stop proj=aa") && !o.contains("trig="));
        o = err(new Runnable() { public void run() { Evt.end("bad why!", "cp", "x y"); } });
        check("end: a word that is not plain becomes other / unknown", o.contains("why=other") && o.contains("trig=unknown"));
        o = err(new Runnable() { public void run() { Evt.raw(true, "a", null); Evt.raw(false, "-", "tlv"); Evt.raw(false, "bad layout!", "x y"); } });
        check("raw: ok / bad lines with plain words; anything else becomes -", o.contains("EVT cp-raw res=ok layout=a why=- seq=") && o.contains("EVT cp-raw res=bad layout=- why=tlv seq=") && o.contains("res=bad layout=- why=- seq="));
        System.out.println(fails == 0 ? "evt: passed" : "evt: FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
