package jmkhud.link;

import java.io.ByteArrayOutputStream;
import java.io.UnsupportedEncodingException;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * JMK's own (AGPL-3.0 compatible). Encode and decode one line of the text wire:
 * <pre>
 *   JC&lt;proto&gt; &lt;seq&gt; &lt;verb&gt; k=v ...        request
 *   JC&lt;proto&gt; &lt;seq&gt; ok|err|unsupported|refused k=v ...   reply
 *   JC&lt;proto&gt; 0 ev &lt;name&gt; k=v ...      event
 * </pre>
 * One line is at most 1024 bytes including the newline. Keys are [a-z][a-z0-9_.]*; a value has no space, '=' or newline:
 * every byte outside [A-Za-z0-9._:/,@-] is written %XX. Unknown keys are the reader's to ignore. decode never throws:
 * a line that does not fit the grammar gives null.
 */
public final class Wire {
    public static final int MAX_LINE = 1024;

    private Wire() {}

    public static boolean plain(int c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
                || c == '.' || c == '_' || c == ':' || c == '/' || c == ',' || c == '@' || c == '-';
    }

    public static String esc(String v) {
        if (v == null) return "";
        byte[] b;
        try { b = v.getBytes("UTF-8"); } catch (UnsupportedEncodingException e) { throw new IllegalStateException(e); }
        StringBuilder s = new StringBuilder(b.length + 8);
        for (byte x : b) {
            int c = x & 0xff;
            if (plain(c)) s.append((char) c);
            else s.append('%').append("0123456789ABCDEF".charAt(c >> 4)).append("0123456789ABCDEF".charAt(c & 15));
        }
        return s.toString();
    }

    /** The decoded value, or null when an escape is bad. */
    public static String unesc(String v) {
        if (v.indexOf('%') < 0) return v;
        ByteArrayOutputStream o = new ByteArrayOutputStream(v.length());
        for (int i = 0; i < v.length(); i++) {
            char c = v.charAt(i);
            if (c == '%') {
                if (i + 2 >= v.length()) return null;
                int h = Character.digit(v.charAt(i + 1), 16), l = Character.digit(v.charAt(i + 2), 16);
                if (h < 0 || l < 0) return null;
                o.write((h << 4) | l);
                i += 2;
            } else if (c < 128) o.write(c);
            else return null;   // a raw non-ASCII character is not allowed on the wire
        }
        try { return new String(o.toByteArray(), "UTF-8"); } catch (UnsupportedEncodingException e) { throw new IllegalStateException(e); }
    }

    public static boolean key(String k) {
        if (k.length() == 0 || k.length() > 40) return false;
        char c0 = k.charAt(0);
        if (c0 < 'a' || c0 > 'z') return false;
        for (int i = 1; i < k.length(); i++) {
            char c = k.charAt(i);
            if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '.')) return false;
        }
        return true;
    }

    private static boolean word(String w) { return key(w); }

    /** The line without its newline. Throws IllegalArgumentException for a frame that cannot be written (a bug of the caller). */
    public static String encode(Frame fr) {
        StringBuilder s = new StringBuilder(96);
        s.append("JC").append(fr.proto).append(' ').append(fr.seq).append(' ');
        if (fr.type.equals("req")) {
            if (!word(fr.name)) throw new IllegalArgumentException("verb " + fr.name);
            s.append(fr.name);
        } else if (fr.type.equals("ev")) {
            if (!word(fr.name)) throw new IllegalArgumentException("event " + fr.name);
            s.append("ev ").append(fr.name);
        } else if (fr.isReply()) s.append(fr.type);
        else throw new IllegalArgumentException("type " + fr.type);
        for (Map.Entry<String, String> e : fr.f.entrySet()) {
            if (!key(e.getKey())) throw new IllegalArgumentException("key " + e.getKey());
            s.append(' ').append(e.getKey()).append('=').append(esc(e.getValue()));
        }
        if (s.length() + 1 > MAX_LINE) throw new IllegalArgumentException("too long");
        return s.toString();
    }

    /** Parse one line (no newline). null when it does not fit the grammar; never throws. */
    public static Frame decode(String line) {
        try {
            if (line == null || line.length() + 1 > MAX_LINE) return null;
            for (int i = 0; i < line.length(); i++) { char c = line.charAt(i); if (c < 0x20 || c > 0x7e) return null; }   // the wire is printable ASCII: everything else is %XX
            String[] t = line.split(" ", -1);
            if (t.length < 3) return null;
            if (!t[0].startsWith("JC") || t[0].length() < 3 || t[0].length() > 9) return null;
            int proto = parseInt(t[0].substring(2));
            long seq = parseLong(t[1]);
            if (proto < 0 || seq < 0) return null;
            String type, name = "";
            int from;
            String w = t[2];
            if (w.equals("ok") || w.equals("err") || w.equals("unsupported") || w.equals("refused")) { type = w; from = 3; }
            else if (w.equals("ev")) {
                if (t.length < 4 || !word(t[3])) return null;
                type = "ev"; name = t[3]; from = 4;
            } else if (word(w)) { type = "req"; name = w; from = 3; }
            else return null;
            Map<String, String> m = new LinkedHashMap<String, String>();
            for (int i = from; i < t.length; i++) {
                String tok = t[i];
                if (tok.length() == 0) return null;   // double space
                int eq = tok.indexOf('=');
                if (eq <= 0) return null;
                String k = tok.substring(0, eq);
                if (!key(k)) return null;
                String v = unesc(tok.substring(eq + 1));
                if (v == null) return null;
                m.put(k, v);
            }
            return new Frame(proto, seq, type, name, m);
        } catch (RuntimeException e) {
            return null;
        }
    }

    private static int parseInt(String s) {
        if (s.length() == 0) return -1;
        for (int i = 0; i < s.length(); i++) if (s.charAt(i) < '0' || s.charAt(i) > '9') return -1;
        return Integer.parseInt(s);
    }

    private static long parseLong(String s) {
        if (s.length() == 0 || s.length() > 18) return -1;
        for (int i = 0; i < s.length(); i++) if (s.charAt(i) < '0' || s.charAt(i) > '9') return -1;
        return Long.parseLong(s);
    }
}
