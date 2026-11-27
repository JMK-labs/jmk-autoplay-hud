package jmkhud.link;

import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * JMK's own (AGPL-3.0 compatible). All service I/O of a process inside a stock app runs on ONE helper thread; the stock thread
 * hands the call over and waits on a latch for at most {@code budgetMs}. A busy helper counts as a failure (null); a second helper
 * is never started. Never a socket connect with a timeout (not supported on Android): a plain connect refuses at once when nobody
 * listens, and the budget covers the rest.
 */
public final class Helper {
    /** Called when an answer arrives after the caller gave up. */
    public interface Late { void late(String what, long ms); }

    private final ExecutorService ex;
    private final AtomicBoolean busy = new AtomicBoolean(false);
    private final Clock clock;
    private final Late late;

    public Helper(Clock clock, Late late) {
        this.clock = clock;
        this.late = late;
        this.ex = Executors.newSingleThreadExecutor(new ThreadFactory() {
            public Thread newThread(Runnable r) {
                Thread t = new Thread(r, Lex.get(Lex.THREAD));
                t.setDaemon(true);
                return t;
            }
        });
    }

    /** The result, or null when the helper is busy, the call threw, or the budget passed (then {@code late} is told when it ends). */
    public <T> T call(final String what, final Callable<T> c, long budgetMs) {
        if (!busy.compareAndSet(false, true)) return null;
        final long t0 = clock.el();
        final AtomicBoolean gaveUp = new AtomicBoolean(false);
        final AtomicBoolean reported = new AtomicBoolean(false);
        Future<T> f;
        try {
            f = ex.submit(new Callable<T>() {
                public T call() throws Exception {
                    try {
                        return c.call();
                    } finally {
                        busy.set(false);
                        if (gaveUp.get() && late != null && reported.compareAndSet(false, true)) late.late(what, clock.el() - t0);
                    }
                }
            });
        } catch (RejectedExecutionException e) {
            busy.set(false);
            return null;
        }
        try {
            return f.get(Math.max(1, budgetMs), TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            gaveUp.set(true);
            if (f.isDone() && late != null && reported.compareAndSet(false, true)) late.late(what, clock.el() - t0);   // finished between the timeout and the flag
            return null;
        } catch (InterruptedException e) {
            gaveUp.set(true);
            Thread.currentThread().interrupt();
            return null;
        } catch (ExecutionException e) {
            return null;
        }
    }

    public boolean isBusy() { return busy.get(); }

    public void shutdown() { ex.shutdownNow(); }
}
