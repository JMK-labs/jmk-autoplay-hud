package com.jmk.hud;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;

/** The count line of every blank: java com.jmk.hud.EndLogTest (one JVM, the cases in order). */
public final class EndLogTest {
    static int fails;

    static void check(String what, boolean ok) {
        if (!ok) { fails++; System.out.println("FAIL " + what); } else System.out.println("ok   " + what);
    }

    /** A stand-in for the stock class: the funnel is sendHudBlank, called by a method with the stock's name. */
    static final class Fake {
        void sendHudBlank() { EndLog.blank(); }
        void disconnected() { sendHudBlank(); }
        void leafiaSourceCheck() { sendHudBlank(); }
        void nS() { sendHudBlank(); }
        void zz() { sendHudBlank(); }
        void somethingLong() { sendHudBlank(); }
    }

    static String run(Runnable r) {
        PrintStream old = System.err;
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        System.setErr(new PrintStream(b));
        try { r.run(); } finally { System.setErr(old); }
        String evt = "";
        for (String l : b.toString().split("\n")) if (l.contains("EVT tbt-end")) evt = l;
        return evt;
    }

    public static void main(String[] a) {
        final Fake f = new Fake();
        String e = run(new Runnable() { public void run() { f.disconnected(); } });
        check("session end: why=session-end proj=cp, no trig, seq and pid", e.contains("why=session-end") && e.contains("proj=cp") && !e.contains("trig=") && e.contains("seq=1") && e.contains("pid=4242"));
        e = run(new Runnable() { public void run() { f.leafiaSourceCheck(); } });
        check("source change: why=source-change", e.contains("why=source-change") && e.contains("seq=2"));
        Keep.endsBy("phone-stop", null);
        e = run(new Runnable() { public void run() { f.nS(); } });
        check("a cause set by Keep wins over the stock name: why=phone-stop", e.contains("why=phone-stop") && !e.contains("trig="));
        e = run(new Runnable() { public void run() { f.nS(); } });
        check("the cause is used once: the next stock end is other, trig=stock-ns", e.contains("why=other") && e.contains("trig=stock-ns"));
        Keep.endsBy("other", "silence");
        e = run(new Runnable() { public void run() { f.zz(); } });
        check("other with the hook name: trig=silence", e.contains("why=other") && e.contains("trig=silence"));
        e = run(new Runnable() { public void run() { f.somethingLong(); } });
        check("a long unknown stock name is other, trig=other", e.contains("why=other") && e.contains("trig=other"));
        System.out.println(fails == 0 ? "endlog: passed" : "endlog: FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
