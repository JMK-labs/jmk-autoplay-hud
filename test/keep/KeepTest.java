package com.jmk.hud;

import java.io.IOException;
import java.net.SocketTimeoutException;
import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;

import jmkhud.link.Clock;
import jmkhud.link.Frame;
import jmkhud.link.HookClient;
import jmkhud.link.Transport;
import jmkhud.link.Wire;

/** One scenario per JVM (Keep keeps its state in statics): java com.jmk.hud.KeepTest <scenario>. */
public final class KeepTest {
    static final List<Frame> asked = new ArrayList<Frame>();
    static final List<Frame> notes = new ArrayList<Frame>();
    static String act = "";            // the service's answer: "", keep, drop, refresh ("" = no service: refused at once)
    static String recheck = "";
    static int fails;

    static void check(String what, boolean ok) {
        if (!ok) { fails++; System.out.println("FAIL " + what); } else System.out.println("ok   " + what);
    }

    static void arm() {
        Transport.Connector c = new Transport.Connector() {
            public Transport.Conn open() throws IOException {
                if (act.length() == 0) throw new IOException("refused");
                return new Transport.Conn() {
                    final LinkedList<String> q = new LinkedList<String>();
                    public void writeLine(String line) {
                        Frame f = Wire.decode(line);
                        if (f == null) return;
                        if (f.name.equals("hello")) q.add(Wire.encode(Frame.reply(1, f.seq, "ok", Frame.kv("proto", "1"))));
                        else if (f.name.equals("keep.ask")) {
                            asked.add(f);
                            q.add(Wire.encode(Frame.reply(1, f.seq, "ok", Frame.kv("act", act, "recheck_ms", recheck.length() == 0 ? null : recheck))));
                        } else if (f.name.equals("keep.note")) notes.add(f);
                    }
                    public String readLine(int timeoutMs) throws IOException {
                        if (q.isEmpty()) throw new SocketTimeoutException();
                        return q.removeFirst();
                    }
                    public int peerUid() { return 0; }
                    public int peerPid() { return 1; }
                    public void close() { }
                };
            }
        };
        HookClient.get(c, new Clock() { public long el() { return System.nanoTime() / 1000000L; } },
                new jmkhud.link.Log() { public void line(String s) { } }, "hud-dipo", "t");
    }

    static void pause(int ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { } }

    public static void main(String[] a) throws Exception {
        String sc = a[0];
        com.daudio.app.dipo.e.u stock = new com.daudio.app.dipo.e.u();
        if (sc.equals("none")) {                       // no service: state 0 ends the display, silence leaves it
            act = ""; arm();
            Keep.state(1);
            check("no service: zero -> the stock code ends it", Keep.zero(stock) == 0);
            check("no service: silence -> left on", Keep.beat(61000) == 0);
        } else if (sc.equals("keep")) {
            act = "keep"; arm();
            check("state 0 before any other state: no question, stock ends", Keep.zero(stock) == 0 && asked.size() == 0);
            Keep.state(1);
            Keep.state(0);
            check("keep: zero -> left", Keep.zero(stock) == 1);
            check("keep: one question with the fields", asked.size() == 1 && asked.get(0).get("src").equals("cp") && asked.get(0).get("why").equals("zero")
                    && asked.get(0).get("st").equals("0") && asked.get(0).get("n").equals("1") && asked.get(0).get("refresh").equals("0")
                    && asked.get(0).get("can_refresh").equals("0") && asked.get(0).get("quiet_ms") != null && asked.get(0).get("since_state_ms") != null);
            check("keep: a second state 0 while held -> left, no second question", Keep.zero(stock) == 1 && asked.size() == 1);
            Keep.state(1);
            Keep.state(0);
            check("keep: after another state the next 0 asks again (n restarts)", Keep.zero(stock) == 1 && asked.size() == 2 && asked.get(1).get("n").equals("1"));
        } else if (sc.equals("drop")) {
            act = "drop"; arm(); Keep.state(3);
            check("drop: zero -> the stock code ends it", Keep.zero(stock) == 0);
            check("drop: silence asks and ends", Keep.beat(70000) == 1 && asked.get(asked.size() - 1).get("why").equals("silence"));
        } else if (sc.equals("refresh")) {
            act = "refresh"; arm(); Keep.state(1);
            com.daudio.app.dipo.e.u.leafiaOwner = new com.daudio.app.dipo.e.b();
            check("refresh: zero -> left", Keep.zero(stock) == 1);
            pause(200);
            check("refresh: the restart ran once; can_refresh=1", com.daudio.app.dipo.e.b.restarts == 1 && asked.get(0).get("can_refresh").equals("1"));
            Keep.state(1); Keep.state(0);
            check("refresh: asked again after a state, answered refresh again -> no second restart in the same route", Keep.zero(stock) == 1);
            pause(200);
            check("refresh: still one restart; refresh=1 is sent", com.daudio.app.dipo.e.b.restarts == 1 && asked.get(1).get("refresh").equals("1"));
        } else if (sc.equals("refreshrecheck")) {
            act = "refresh"; recheck = "150"; arm(); Keep.state(1); Keep.state(0);
            com.daudio.app.dipo.e.u.leafiaOwner = new com.daudio.app.dipo.e.b();
            check("refresh with recheck_ms: zero -> left, the restart ran once", Keep.zero(stock) == 1);
            pause(500);
            check("refresh with recheck_ms: the same question came again after the time with refresh=1 (a refresh answer counts as keep)",
                    asked.size() >= 2 && asked.get(1).get("why").equals("zero") && asked.get(1).get("refresh").equals("1") && asked.get(1).get("n").equals("2")
                    && com.daudio.app.dipo.e.b.restarts == 1);
        } else if (sc.equals("norefresh")) {
            act = "refresh"; arm(); Keep.state(1);
            check("refresh without a way to refresh: left, nothing restarted", Keep.zero(stock) == 1 && asked.get(0).get("can_refresh").equals("0") && com.daudio.app.dipo.e.b.restarts == 0);
        } else if (sc.equals("silence")) {
            act = "keep"; arm(); Keep.state(1);
            check("silence under a minute: no question", Keep.beat(59999) == 0 && asked.size() == 0);
            check("silence over a minute, keep: left, one question", Keep.beat(61000) == 0 && asked.size() == 1);
            check("silence: not asked again at the next tick", Keep.beat(66000) == 0 && asked.size() == 1);
        } else if (sc.equals("recheck")) {
            act = "keep"; recheck = "150"; arm(); Keep.state(1);
            check("recheck: zero -> left", Keep.zero(stock) == 1);
            act = "drop";
            pause(500);
            check("recheck: the question came again after the time, the answer drop ended the display", asked.size() == 2 && com.daudio.app.dipo.e.u.blanks == 1);
        } else if (sc.equals("busy")) {
            act = "keep"; arm(); Keep.state(1);
            Callout.flying = true;
            check("hotspot question in flight: no keep question, today's behaviour", Keep.zero(stock) == 0 && asked.size() == 0 && Keep.beat(61000) == 0);
        } else if (sc.equals("notes")) {
            act = "keep"; arm();
            Keep.state(1); Keep.state(3); Keep.state(1);
            pause(100);
            check("notes: on a change, at most one a second", notes.size() == 1 && notes.get(0).get("src").equals("cp") && notes.get(0).get("st").equals("1")
                    && notes.get(0).get("reason").matches("[a-z0-9-]{1,24}") && notes.get(0).get("since_state_ms") != null);
            Keep.ended("session-end");
            pause(1100);
            Keep.state(1);
            pause(100);
            check("notes: after the second a new change is sent, the end word is a plain word", notes.size() >= 1 && notes.get(notes.size() - 1).get("reason").matches("[a-z0-9-]{1,24}"));
            int before = asked.size();
            Keep.ended("session-end");
            Keep.state(0);
            check("ended: the next state 0 is not asked (nothing live), the stock code ends it", Keep.zero(stock) == 0 && asked.size() == before);
        }
        System.out.println(fails == 0 ? "keep: " + sc + " passed" : "keep: " + sc + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
