package jmkhud.link.android;
import jmkhud.link.Transport;
public class LocalSockets {
    /** The test sets this before the first question. */
    public static Transport.Connector TEST;
    public static Transport.Connector connector(String name) { return TEST; }
}
