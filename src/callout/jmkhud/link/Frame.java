package jmkhud.link;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * JMK's own (AGPL-3.0 compatible). One parsed line of the text wire.
 * type: "req" (name = the verb), "ok" / "err" / "unsupported" / "refused" (a reply, name empty), "ev" (name = the event).
 * Values are decoded; keys keep their order.
 */
public final class Frame {
    public final int proto;
    public final long seq;
    public final String type;
    public final String name;
    public final Map<String, String> f;

    public Frame(int proto, long seq, String type, String name, Map<String, String> f) {
        this.proto = proto;
        this.seq = seq;
        this.type = type;
        this.name = name == null ? "" : name;
        this.f = f == null ? new LinkedHashMap<String, String>() : f;
    }

    public String get(String key) { return f.get(key); }

    public String get(String key, String dflt) {
        String v = f.get(key);
        return v == null ? dflt : v;
    }

    /** The number behind {@code key}, or {@code dflt} when missing or not a number. */
    public long num(String key, long dflt) {
        String v = f.get(key);
        if (v == null) return dflt;
        try { return Long.parseLong(v); } catch (NumberFormatException e) { return dflt; }
    }

    public boolean isReply() { return type.equals("ok") || type.equals("err") || type.equals("unsupported") || type.equals("refused"); }

    public static Frame request(int proto, long seq, String verb, Map<String, String> f) { return new Frame(proto, seq, "req", verb, f); }

    public static Frame reply(int proto, long seq, String type, Map<String, String> f) { return new Frame(proto, seq, type, "", f); }

    public static Frame event(int proto, String name, Map<String, String> f) { return new Frame(proto, 0, "ev", name, f); }

    /** A small helper for building field maps in order: kv("a","1","b","2"). */
    public static Map<String, String> kv(String... pairs) {
        Map<String, String> m = new LinkedHashMap<String, String>();
        for (int i = 0; i + 1 < pairs.length; i += 2) if (pairs[i + 1] != null) m.put(pairs[i], pairs[i + 1]);
        return m;
    }
}
