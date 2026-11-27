package jmkhud.link;

import java.io.IOException;
import java.net.SocketTimeoutException;

/**
 * android.net.LocalSocket reports a read timeout (SO_RCVTIMEO expiring, EAGAIN) as a plain IOException ("Try again"), not as a
 * SocketTimeoutException (Android 4.4). The one rule for every reader, pure so the Mac tests run the rule the car runs.
 */
public final class ReadTimeout {
    private ReadTimeout() { }

    /** The exception to throw for an IOException out of a read that waited {@code waitedMs} of a {@code timeoutMs} limit (0 = none). */
    public static IOException map(IOException e, long waitedMs, int timeoutMs) {
        if (e instanceof SocketTimeoutException) return e;
        String m = String.valueOf(e.getMessage());
        if (timeoutMs > 0 && (m.contains("Try again") || m.contains("EAGAIN") || waitedMs >= timeoutMs)) return new SocketTimeoutException(m);
        return e;
    }
}
