package jmkhud.link;

/** JMK's own (AGPL-3.0 compatible). One monotonic clock: SystemClock.elapsedRealtime() in ms on the car, a fake in tests. */
public interface Clock {
    long el();
}
