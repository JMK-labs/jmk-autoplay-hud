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
    static int delayMs;                 // the service answers this late
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
                        if (delayMs > 0 && q.size() == 1) {   // the answer of the question comes this late (the hello reply was the first line)
                            if (delayMs >= timeoutMs) { pause(timeoutMs); throw new SocketTimeoutException(); }
                            pause(delayMs);
                        }
                        if (q.isEmpty()) throw new SocketTimeoutException();
                        return q.removeFirst();
                    }
                    public int peerUid() { return 0; }
                    public int peerPid() { return 1; }
                    public void close() { }
                };
            }
        };
        jmkhud.link.android.LocalSockets.TEST = c;
    }

    static Object field(String name) {
        try { java.lang.reflect.Field f = Keep.class.getDeclaredField(name); f.setAccessible(true); return f.get(null); } catch (Exception e) { return null; }
    }

    static void pause(int ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { } }

    public static void main(String[] a) throws Exception {
        String sc = a[0];
        com.daudio.app.dipo.e.u stock = new com.daudio.app.dipo.e.u();
        if (!sc.startsWith("restart")) {       // every other case runs in a process that has seen its first state already
            try { java.lang.reflect.Field f = Keep.class.getDeclaredField("firstSeen"); f.setAccessible(true); f.setBoolean(null, true); } catch (Exception e) { throw new RuntimeException(e); }
        }
        if (sc.equals("none")) {                       // no service: the display is left as drawn (only an answer "drop" ends it)
            act = ""; arm();
            Keep.state(1);
            java.io.PrintStream olderr = System.err; java.io.ByteArrayOutputStream eb = new java.io.ByteArrayOutputStream(); System.setErr(new java.io.PrintStream(eb));
            boolean kept = Keep.zero(stock) == 1;
            System.setErr(olderr);
            check("no service: zero -> left as drawn", kept && Keep.takeCause() == null);
            check("no service: counted as other / core-absent", eb.toString().contains("EVT tbt-end why=other proj=cp trig=core-absent"));
            check("no service: silence -> left on", Keep.beat(61000) == 0);
        } else if (sc.equals("late")) {                // the answer comes after the hook gave up: left as drawn for now, the answer is applied when it comes
            act = "drop"; delayMs = 900; arm(); Keep.state(1);
            check("late answer: zero returns at once, left as drawn", Keep.zero(stock) == 1 && Keep.takeCause() == null && com.daudio.app.dipo.e.u.blanks == 0);
            check("late answer: a second state 0 meanwhile asks nothing new (the question is in flight)", Keep.zero(stock) == 1 && asked.size() <= 1);
            pause(1500);
            check("late answer: the drop that came late ended the display", com.daudio.app.dipo.e.u.blanks == 1);
            String[] c = Keep.takeCause();
            check("late answer: the cause is phone-stop / late", c != null && c[0].equals("phone-stop") && c[1].equals("late"));
        } else if (sc.equals("latekeep")) {            // a late keep ends nothing and clears "no answer"
            act = "keep"; delayMs = 900; arm(); Keep.state(1);
            check("late keep: left as drawn", Keep.zero(stock) == 1);
            pause(1500);
            check("late keep: nothing ended, no cause", com.daudio.app.dipo.e.u.blanks == 0 && Keep.takeCause() == null);
            delayMs = 0;
            check("late keep: the next state 0 is held without a new question", Keep.zero(stock) == 1 && asked.size() == 1);
        } else if (sc.equals("latestale")) {           // a state came before the late answer: the answer belongs to the old one and is dropped
            act = "drop"; delayMs = 900; arm(); Keep.state(1);
            check("stale: zero left as drawn", Keep.zero(stock) == 1);
            Keep.state(1); Keep.state(3);
            pause(1500);
            check("stale: the late drop is not applied after a new state", com.daudio.app.dipo.e.u.blanks == 0 && Keep.takeCause() == null);
        } else if (sc.equals("again")) {               // held without an answer: asked again with the next update until an answer comes
            act = ""; arm(); Keep.state(1);
            check("again: no service: left as drawn", Keep.zero(stock) == 1);
            check("again: the next update asks again (still no service), still left", Keep.zero(stock) == 1);
            act = "keep";
            check("again: the service is back: the next update asks, the answer keep is held", Keep.zero(stock) == 1 && asked.size() == 1);
            check("again: after an answer a further state 0 asks nothing", Keep.zero(stock) == 1 && asked.size() == 1);
        } else if (sc.equals("againdrop")) {
            act = ""; arm(); Keep.state(1);
            check("againdrop: no service: left as drawn", Keep.zero(stock) == 1);
            act = "drop";
            check("againdrop: the service is back and says drop: the next update ends it", Keep.zero(stock) == 0);
            String[] c = Keep.takeCause();
            check("againdrop: the cause is phone-stop", c != null && c[0].equals("phone-stop"));
        } else if (sc.equals("gate")) {                // three questions without an answer close the gate: still left as drawn
            act = ""; arm(); Keep.state(1);
            boolean all = true;
            for (int i = 0; i < 6; i++) { all &= Keep.zero(stock) == 1; Keep.state(1); }
            check("closed gate: every state 0 -> left as drawn, never an end", all && Keep.takeCause() == null);
        } else if (sc.equals("restart")) {             // the first state of a process asks once (a restart during a live session); never again, never an end
            act = "refresh"; arm();
            com.daudio.app.dipo.e.u.leafiaOwner = new com.daudio.app.dipo.e.b();
            Keep.state(1);
            pause(200);
            check("restart: the first state asks once, why=restart", asked.size() == 1 && asked.get(0).get("why").equals("restart") && asked.get(0).get("st").equals("1"));
            check("restart: the answer refresh restarted the route guidance once", com.daudio.app.dipo.e.b.restarts == 1);
            Keep.state(3); Keep.state(1);
            check("restart: later states do not ask", asked.size() == 1);
            check("restart: nothing was ended", com.daudio.app.dipo.e.u.blanks == 0 && Keep.zero(stock) == 1);
        } else if (sc.equals("restartkeep")) {         // a plain keep at the first state: nothing was restarted, so nothing is counted
            act = "keep"; arm();
            java.io.PrintStream olderr = System.err; java.io.ByteArrayOutputStream eb = new java.io.ByteArrayOutputStream(); System.setErr(new java.io.PrintStream(eb));
            Keep.state(1); pause(200);
            System.setErr(olderr);
            check("restart keep: one question, no restart line", asked.size() == 1 && asked.get(0).get("why").equals("restart") && !eb.toString().contains("why=restart"));
        } else if (sc.equals("restartnone")) {         // no service: the first state does not fail and ends nothing
            act = ""; arm();
            Keep.state(1);
            check("restart without a service: no question reached it, nothing ended", asked.size() == 0 && com.daudio.app.dipo.e.u.blanks == 0 && Keep.zero(stock) == 1);
        } else if (sc.equals("separate")) {            // the question and the note have their own client
            act = "keep"; arm(); Keep.state(1);
            Keep.zero(stock);
            Object ac = field("askClient"), nc = field("noteClient");
            check("separate clients: both exist and are two objects", ac != null && nc != null && ac != nc);
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
            check("drop: zero -> the stock code ends it, the cause is phone-stop", Keep.zero(stock) == 0);
            String[] c = Keep.takeCause();
            check("drop: the cause is taken once", c != null && c[0].equals("phone-stop") && c[1] == null && Keep.takeCause() == null);
            check("drop: silence asks and ends", Keep.beat(70000) == 1 && asked.get(asked.size() - 1).get("why").equals("silence"));
            String[] s = Keep.takeCause();
            check("drop: silence cause is other / silence", s != null && s[0].equals("other") && s[1].equals("silence"));
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
            String[] r = Keep.takeCause();
            check("recheck: the cause is phone-stop / recheck", r != null && r[0].equals("phone-stop") && r[1].equals("recheck"));
        } else if (sc.equals("busy")) {
            act = "keep"; arm(); Keep.state(1);
            Callout.flying = true;
            check("hotspot question in flight: no keep question, the display is left as drawn", Keep.zero(stock) == 1 && asked.size() == 0 && Keep.beat(61000) == 0);
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
            String[] z = Keep.takeCause();
            check("ended: state 0 with nothing live is counted as phone-stop", z != null && z[0].equals("phone-stop"));
        }
        System.out.println(fails == 0 ? "keep: " + sc + " passed" : "keep: " + sc + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
