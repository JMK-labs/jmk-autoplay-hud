package jmkhud.link;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.atomic.AtomicLong;

/**
 * JMK's own (AGPL-3.0 compatible).
 */
public final class HookClient {
    public static final class Answer {
        /** true when the hook should leave its own start out. */
        public final boolean hold;
        /** the call id the service gave, or "-". */
        public final String hc;
        /** the attempt id the service gave, or "-". */
        public final String aid;
        /** true when an answer came back in the budget. */
        public final boolean answered;
        public final long ms;
        /** Why there is (no) answer; "timeout" when none came in time. */
        public final String how;

        Answer(boolean hold, String hc, String aid, boolean answered, long ms, String how) {
            this.hold = hold; this.hc = hc; this.aid = aid; this.answered = answered; this.ms = ms; this.how = how;
        }
    }

    private static final String REASON = Lex.get(Lex.BRIDGE_SPP);
    private static final int PROTO = 1;
    /** The helper keeps listening this long after the caller's budget, only to COUNT an answer that came too late (and to stay busy meanwhile). */
    private static final int LATE_MS = 700;

    private final Transport.Connector connector;
    private final Clock clock;
    private final Log log;
    private final String role, ver;
    private final Helper helper;
    private final Gate gate;
    private final AtomicLong seq = new AtomicLong(1);
    private static HookClient shared;

    /**
     * One client per process: every instance owns a helper thread, so a hook that built a client per call would leak one thread per
     * hotspot question. The first call's arguments win.
     */
    public static synchronized HookClient get(Transport.Connector connector, Clock clock, Log log, String role, String ver) {
        if (shared == null) shared = new HookClient(connector, clock, log, role, ver);
        return shared;
    }

    public HookClient(Transport.Connector connector, final Clock clock, final Log log, String role, String ver) {
        this.connector = connector;
        this.clock = clock;
        this.log = log;
        this.role = role;
        this.ver = ver;
        this.helper = new Helper(clock, null);   // a late ANSWER is counted by this class (exchange), not "the helper ended late"
        this.gate = new Gate(clock, new Gate.Listener() {
            public void changed(boolean open) { log.line(Lex.get(Lex.GATE_LINE) + (open ? "open" : "closed") + Lex.get(Lex.SERVICE)); }
        });
    }

    /** Asks whether the hook may leave its own hotspot start out. Never throws; at most {@code budgetMs} of the caller's time. */
    public Answer hotspotOn(final int budgetMs) {
        final long t0 = clock.el();
        try {
            if (!gate.allow()) return absent(t0, Lex.get(Lex.GATE));
            final long myseq = seq.getAndAdd(2);
            final Pending pend = new Pending(t0);
            final Frame[] got = helper.call(Lex.get(Lex.HOTSPOT_ON), new Callable<Frame[]>() {
                public Frame[] call() throws Exception { return exchange(myseq, budgetMs, pend); }
            }, budgetMs);
            long ms = clock.el() - t0;
            if (got == null) pend.abandon(clock, log);   // from now on an answer that arrives is logged as late
            if (got == REFUSED) {   // nobody listens / not root: a clear "absent", the service is not acting
                gate.failure();
                return new Answer(false, "-", "-", false, ms, "refused");
            }
            if (got == null || got[1] == null) {
                gate.failure();
                log.line(Lex.get(Lex.NO_ANSWER) + ms + Lex.get(Lex.OWN_START));
                return new Answer(false, "-", "-", false, ms, "timeout");
            }
            gate.success();
            Frame r = got[1];
            boolean hold = (r.type.equals("ok") || r.type.equals("refused")) && "1".equals(r.get(Lex.get(Lex.SKIP)));
            String hc = r.get("hc", "-"), aid = r.get("aid", "-");
            log.line(Lex.get(Lex.CALL_LINE) + hc + " caller=" + role + " reason=" + REASON + " aid=" + aid
                    + " el=" + clock.el() + " ms=" + ms + Lex.get(Lex.HOLD) + (hold ? 1 : 0));
            return new Answer(hold, hc, aid, true, ms, "answered");
        } catch (Throwable t) {
            return absent(t0, "refused");   // an exception in this client's own code: nothing was asked, nothing acted
        }
    }

    /** One call whose caller may give up before the answer comes; the late answer is logged once. */
    private static final class Pending {
        final long t0;
        private boolean abandoned, reported;
        private Frame answer;

        Pending(long t0) { this.t0 = t0; }

        synchronized void abandon(Clock clock, Log log) {
            abandoned = true;
            report(clock, log);
        }

        synchronized void answered(Frame r, Clock clock, Log log) {
            answer = r;
            report(clock, log);
        }

        private void report(Clock clock, Log log) {
            if (abandoned && answer != null && !reported) {
                reported = true;
                log.line(Lex.get(Lex.LATE) + (clock.el() - t0) + Lex.get(Lex.HOLD) + ("1".equals(answer.get(Lex.get(Lex.SKIP))) ? 1 : 0));
            }
        }
    }

    /** The answer to {@link #ask}: the reply frame when one came in the budget, else null; how is as in {@link Answer}. */
    public static final class Reply {
        public final Frame frame;
        public final String how;
        public final long ms;

        Reply(Frame frame, String how, long ms) { this.frame = frame; this.how = how; this.ms = ms; }
    }

    /**
     * Any request with an answer, under the same rules as {@link #hotspotOn}: the one helper thread of the process, at most
     * {@code budgetMs} of the caller's time, never throws. dl= is set from the budget. how: "answered" (frame set, whatever its type),
     * "refused" (nobody listens, the server is not root, or hello was not answered ok), "gate", "timeout".
     */
    public Reply ask(final String verb, final Map<String, String> fields, final int budgetMs) {
        final long t0 = clock.el();
        try {
            if (!gate.allow()) return new Reply(null, Lex.get(Lex.GATE), clock.el() - t0);
            final long myseq = seq.getAndAdd(2);
            final Frame[] got = helper.call(verb, new Callable<Frame[]>() {
                public Frame[] call() throws Exception {
                    Map<String, String> m = new java.util.LinkedHashMap<String, String>();
                    if (fields != null) m.putAll(fields);
                    m.put("dl", String.valueOf(Math.max(1, budgetMs - 20)));
                    return exchange(myseq, verb, m, budgetMs);
                }
            }, budgetMs);
            long ms = clock.el() - t0;
            if (got == REFUSED) { gate.failure(); return new Reply(null, "refused", ms); }
            if (got == null || got[1] == null) {
                gate.failure();
                log.line(Lex.get(Lex.NO_ANSWER_ANY) + verb + " " + ms + Lex.get(Lex.MS));
                return new Reply(null, "timeout", ms);
            }
            gate.success();
            return new Reply(got[1], "answered", ms);
        } catch (Throwable t) {
            return new Reply(null, "refused", clock.el() - t0);
        }
    }

    /** A one-way line (noreply=1): nobody waits for it, nothing is read back, never throws. */
    public void tell(final String verb, final Map<String, String> fields) {
        try {
            if (!gate.allow()) return;
            helper.call(verb, new Callable<Boolean>() {
                public Boolean call() throws Exception {
                    Transport.Conn c = open();
                    if (c == null) return Boolean.FALSE;
                    try {
                        c.writeLine(Wire.encode(Frame.request(PROTO, seq.getAndIncrement(), "hello", Frame.kv("role", role, "ver", ver))));
                        Map<String, String> m = new java.util.LinkedHashMap<String, String>();
                        if (fields != null) m.putAll(fields);
                        m.put("noreply", "1");
                        c.writeLine(Wire.encode(Frame.request(PROTO, seq.getAndIncrement(), verb, m)));
                        return Boolean.TRUE;
                    } finally { c.close(); }
                }
            }, 100);
        } catch (Throwable t) { /* a one-way line is never worth a failure */ }
    }

    /** [0] = the answer to hello, [1] = the answer to the request (null when it did not come). */
    private Frame[] exchange(long myseq, String verb, Map<String, String> fields, int budgetMs) throws IOException {
        Transport.Conn c = open();
        if (c == null) return REFUSED;
        try {
            c.writeLine(Wire.encode(Frame.request(PROTO, myseq, "hello", Frame.kv("role", role, "ver", ver))));
            c.writeLine(Wire.encode(Frame.request(PROTO, myseq + 1, verb, fields)));
            Frame h = Wire.decode(c.readLine(Math.max(1, budgetMs)));
            if (h == null || !h.type.equals("ok")) return REFUSED;
            return new Frame[] { h, Wire.decode(c.readLine(Math.max(1, budgetMs))) };
        } finally {
            c.close();
        }
    }

    private Answer absent(long t0, String how) { return new Answer(false, "-", "-", false, clock.el() - t0, how); }

    private static final Frame[] REFUSED = new Frame[2];

    /** [0] = the answer to hello, [1] = the answer to the request (null when it did not come). */
    private Frame[] exchange(long myseq, int budgetMs, Pending pend) throws IOException {
        Transport.Conn c = open();
        if (c == null) return REFUSED;
        try {
            c.writeLine(Wire.encode(Frame.request(PROTO, myseq, "hello", Frame.kv("role", role, "ver", ver))));
            c.writeLine(Wire.encode(Frame.request(PROTO, myseq + 1, Lex.get(Lex.HOTSPOT_ON), Frame.kv("reason", REASON, "caller", role, "dl", String.valueOf(Math.max(1, budgetMs - 20))))));
            Frame h = Wire.decode(c.readLine(Math.max(1, budgetMs) + LATE_MS));
            if (h == null || !h.type.equals("ok")) {
                // hello was not answered ok (denied, an unsupported version, busy over the cap, a closed connection): the service
                // has done nothing, so this is "refused", never "timeout" (only a timeout makes the hook look at state 12)
                if (h != null && h.type.equals("unsupported")) log.line(Lex.get(Lex.UNSUPPORTED) + PROTO + " max=" + h.get("maxproto", "?"));
                else if (h != null) log.line(Lex.get(Lex.HELLO_NOT_OK) + h.type + " " + h.get("why", "-") + ")");
                return REFUSED;
            }
            Frame r = Wire.decode(c.readLine(Math.max(1, budgetMs) + LATE_MS));
            if (r != null) pend.answered(r, clock, log);
            return new Frame[] { h, r };
        } finally {
            c.close();
        }
    }

    /** A connection to a server that is root, or null (and a line). */
    private Transport.Conn open() {
        Transport.Conn c;
        try {
            c = connector.open();
        } catch (IOException e) {
            log.line(Lex.get(Lex.CONNECT_FAILED) + e.getMessage() + ")");
            return null;
        }
        int uid = c.peerUid();
        if (uid != 0) {
            log.line(Lex.get(Lex.SERVER_UID) + uid + Lex.get(Lex.NOT_ROOT));
            c.close();
            return null;
        }
        return c;
    }
}
