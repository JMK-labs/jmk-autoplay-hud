package jmkhud.link;

/** JMK's own (AGPL-3.0 compatible). One log line per call; the caller decides the file or the logcat tag. */
public interface Log {
    void line(String s);
}
