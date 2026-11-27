package jmkhud.link;

/**
 * JMK's own (AGPL-3.0 compatible). After {@code failures} calls in a row without an answer no call is made for {@code openMs}; one
 * line per change. No timer thread: the clock is read on allow().
 */
public final class Gate {
    public interface Listener { void changed(boolean open); }

    private final Clock clock;
    private final int failures;
    private final long openMs;
    private final Listener listener;
    private int fails;
    private long openUntil = -1;
    private boolean open;

    public Gate(Clock clock, int failures, long openMs, Listener listener) {
        this.clock = clock;
        this.failures = failures;
        this.openMs = openMs;
        this.listener = listener;
    }

    public Gate(Clock clock, Listener listener) { this(clock, 3, 60000, listener); }

    public synchronized boolean allow() {
        if (!open) return true;
        if (clock.el() >= openUntil) { setOpen(false); fails = 0; return true; }
        return false;
    }

    public synchronized void success() {
        fails = 0;
        if (open) setOpen(false);
    }

    public synchronized void failure() {
        if (open) return;
        if (++fails >= failures) { openUntil = clock.el() + openMs; setOpen(true); }
    }

    public synchronized boolean isOpen() { return open && clock.el() < openUntil; }

    private void setOpen(boolean o) {
        open = o;
        if (listener != null) listener.changed(o);
    }
}
