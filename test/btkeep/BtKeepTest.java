package com.jmk.hud;

/** One scenario per JVM: java com.jmk.hud.BtKeepTest <scenario>. The scenarios "noflags" and "noprop" run with a class path that lacks the class they read. */
public final class BtKeepTest {
    static int fails;

    static void check(String what, boolean ok) {
        if (!ok) { fails++; System.out.println("FAIL " + what); } else System.out.println("ok   " + what);
    }

    static void set(boolean wireless, boolean usb, String sw) {
        try {
            Class.forName("com.ev6.cpwl.Bridge").getMethod("set", boolean.class, boolean.class).invoke(null, wireless, usb);
        } catch (Throwable t) { /* the scenario without the class */ }
        try {
            Class.forName("android.os.SystemProperties").getField("value").set(null, sw);
        } catch (Throwable t) { /* the scenario without the class */ }
    }

    public static void main(String[] a) throws Exception {
        String sc = a[0];
        if (sc.equals("wireless")) {
            set(true, false, "");
            check("wireless, switch absent (= on): the connect call is left out", BtKeep.keep(true));
            set(true, false, "1");
            check("wireless, switch 1: left out", BtKeep.keep(true));
            set(true, true, "1");
            check("wireless with the USB flag also set: still left out (the session is wireless)", BtKeep.keep(true));
            check("a disconnect call (false) is never left out", !BtKeep.keep(false));
        } else if (sc.equals("off")) {
            set(true, false, "0");
            check("wireless, switch 0: the stock code runs", !BtKeep.keep(true));
        } else if (sc.equals("wired")) {
            set(false, true, "");
            check("wired (USB) CarPlay: the stock code runs", !BtKeep.keep(true));
            set(false, false, "");
            check("no wireless session: the stock code runs", !BtKeep.keep(true));
        } else if (sc.equals("ended")) {
            set(true, false, "");
            BtKeep.start(1);
            BtKeep.end(1);
            set(false, false, "");
            check("after a wireless session ended (no session now): no time rule, the stock code runs", !BtKeep.keep(true));
            BtKeep.start(0);
            check("a wired session started: still stock", !BtKeep.keep(true));
        } else if (sc.equals("noflags")) {
            check("the bridge class cannot be read: the stock code runs", !BtKeep.keep(true));
        } else if (sc.equals("noprop")) {
            set(true, false, "");
            check("the system properties cannot be read: the stock code runs", !BtKeep.keep(true));
        } else if (sc.equals("log")) {
            set(true, false, "");
            BtKeep.keep(true);
            String last = android.util.Log.LINES.get(android.util.Log.LINES.size() - 1);
            check("one log line with the decision and its reason", last.startsWith("BtKeep: connect=true wireless=true usb=false switch=on") && last.contains("-> kept (wireless)"));
            BtKeep.start(1); BtKeep.end(1);
            check("session start and end are logged", android.util.Log.LINES.contains("BtKeep: session started mode=1") && android.util.Log.LINES.contains("BtKeep: session ended mode=1"));
        }
        System.out.println(fails == 0 ? "btkeep: " + sc + " passed" : "btkeep: " + sc + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
