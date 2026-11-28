package android.os;
public class Handler {
    private static final java.util.Timer T = new java.util.Timer("stub-handler", true);
    private final java.util.Map<Runnable, java.util.TimerTask> tasks = new java.util.HashMap<Runnable, java.util.TimerTask>();
    public Handler(Looper l) { }
    public boolean post(Runnable r) { r.run(); return true; }
    public boolean postDelayed(final Runnable r, long ms) {
        java.util.TimerTask t = new java.util.TimerTask() { public void run() { r.run(); } };
        synchronized (tasks) { tasks.put(r, t); }
        T.schedule(t, ms);
        return true;
    }
    public void removeCallbacks(Runnable r) {
        java.util.TimerTask t;
        synchronized (tasks) { t = tasks.remove(r); }
        if (t != null) t.cancel();
    }
}
