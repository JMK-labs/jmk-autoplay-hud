package com.jmk.hud;

import java.lang.reflect.Field;
import java.util.WeakHashMap;

/**
 * jmk-autoplay-hud 0.1.11 (AGPL-3.0, as this package): the near-turn layout ("big picture") filter of the patched
 * HKMC_GPM (Android Auto) and HKMC_DiPO (CarPlay) builds.
 *
 * Leafia's Korean builds (NEEV.KOR.03-r8 lanes-v5, com.leafia.kr) draw the near-turn layout when the remaining distance
 * to the turn is 0..GUIDE_WINDOW (457 m): LeafiaStandard.format (Android Auto, from LeafiaTurn.standard) and
 * LeafiaStandard.stock (CarPlay, from LeafiaCpStandard.format) take the remaining metres, and a value outside that
 * window (or -1) gives the far layout. Two hooks put this filter in front of that value:
 *
 *   LeafiaTurn.standard        meters = Near.aa(event, side, meters)
 *   LeafiaTurn.reset                    Near.aaForget()
 *   LeafiaCpStandard.format    meters = Near.cp(route guidance of the component, facts, meters)
 *   LeafiaCpStandard.routeReset          Near.cpForget(route guidance of the component)
 *
 * What it changes (ported from an AGPL-3.0 Korean-firmware mod code base (near-turn fix, 2.4.4 generation):
 * the near-turn rules, AGPL-3.0; the
 * method, not its code, adapted to Leafia's fixed window):
 *
 *  1. Hysteresis (both): a turn whose layout went near stays near until the distance is over the window plus
 *     EXIT_MARGIN (the bar stays full); in again at the window. A new turn (another event, side, maneuver index or
 *     type, or the distance up by more than NEW_TURN_JUMP) starts over. Distance wobble at 457 m flipped the picture.
 *  2. put-off (CarPlay): when the maneuver index changes and that update's distance (item 10) is the previous turn's
 *     last distance, it is the previous turn's (Naver Map sends the new index with the old distance): this update
 *     gets the far layout, once per turn. Before, the next turn's near picture flashed for about a second.
 *  3. jump-hold (CarPlay): when the distance of the same turn jumps up (KakaoNavi sends the next turn's distance with
 *     the old index first, the new index 30-130 ms later) and would still be near, the previous frame's distance is
 *     given once; the next update decides. Before, the passed turn's picture flashed with the new distance's bar.
 *
 * Every state is forgotten when CarPlay's route guidance is not "route set" (1) or is reset. Nothing here ever throws:
 * any failure gives back the metres as they came (Leafia's own behaviour).
 */
public final class Near {
    /** Leafia's LeafiaStandard.GUIDE_WINDOW (m): near from 0 to this */
    static final int WINDOW = 457;
    /** a near turn goes far only above WINDOW + this (the upstream near-exit margin) */
    static final int EXIT_MARGIN = 50;
    /** the same turn's distance up by more than this: a new turn (CarPlay: a jump to hold once) */
    static final int NEW_TURN_JUMP = 100;
    /** a distance at or under PASS_NEAR that rises more than PASS_RISE: the turn was passed (CarPlay jump-hold) */
    static final int PASS_NEAR = 30, PASS_RISE = 20;
    /** a rise of at least RISE_MIN within RISE_MS before the index changes is the next turn's distance: no put-off */
    static final int RISE_MIN = 10;
    static final long RISE_MS = 500L;
    /** CarPlay route guidance objects followed at most (as LeafiaCpStandard's MAX_TRACKED) */
    static final int MAX_TRACKED = 64;
    /** iAP2 RouteGuidanceState "route set" */
    static final int ROUTE_SET = 1;

    /** the time in ms (monotonic); tests set clock */
    static long clock = -1L;

    private Near() {
    }

    static long now() {
        return clock >= 0 ? clock : System.nanoTime() / 1000000L;
    }

    /** the metres to show for a distance the layout keeps near or not (window, hysteresis) */
    static int window(boolean[] on, int meters) {
        if (meters <= WINDOW) {
            on[0] = true;
            return meters;
        }
        if (on[0] && meters <= WINDOW + EXIT_MARGIN) return WINDOW;
        on[0] = false;
        return meters;
    }

    // ------------------------------------------------------------------------------------------------ Android Auto
    private static int aaEvent = -1, aaSide = -1, aaLast = -1;
    private static final boolean[] AA_ON = new boolean[1];

    /** LeafiaTurn.standard: the emitted turn (event, side) and its metres (-1: none yet) */
    public static synchronized int aa(int event, int side, int meters) {
        try {
            if (meters < 0) return meters;
            if (event != aaEvent || side != aaSide || (aaLast >= 0 && meters > aaLast + NEW_TURN_JUMP)) AA_ON[0] = false;
            aaEvent = event;
            aaSide = side;
            aaLast = meters;
            return window(AA_ON, meters);
        } catch (Throwable t) {
            return meters;
        }
    }

    /** LeafiaTurn.reset: Android Auto's guidance ended (or the turn memory was reset) */
    public static synchronized void aaForget() {
        aaEvent = -1;
        aaSide = -1;
        aaLast = -1;
        AA_ON[0] = false;
    }

    // ------------------------------------------------------------------------------------------------ CarPlay
    /** one display component's near-turn state (the key of the map: DiPO's route guidance object e/c) */
    static final class Cp {
        boolean keyed;
        int index, type;
        /** the last distance taken for the keyed turn (-1: none) */
        int last = -1;
        /** what the last taken update was given (for jump-hold: the same frame again) */
        int shown = -1;
        final boolean[] on = new boolean[1];
        /** a jump held once (-1: none) */
        int jump = -1;
        /** the last taken distance was a rise (and when) */
        boolean rose;
        long roseAt;
        /** the turn put off once */
        boolean putOff;
        int putOffIndex, putOffType;

        void forget() {
            keyed = false;
            last = -1;
            shown = -1;
            on[0] = false;
            jump = -1;
            rose = false;
            putOff = false;
        }
    }

    private static final WeakHashMap<Object, Cp> CP = new WeakHashMap<Object, Cp>();
    private static Class<?> bdClass;
    private static Field bdField;

    /** the current maneuver index of DiPO's route guidance (field bd: mRouteGuidanceManeuverCurrentList), -1 if none */
    static int index(Object c) throws Exception {
        Class<?> k = c.getClass();
        if (k != bdClass) {
            Field f = k.getDeclaredField("bd");
            f.setAccessible(true);
            bdField = f;
            bdClass = k;
        }
        Object v = bdField.get(c);
        if (!(v instanceof int[])) return -1;
        int[] list = (int[]) v;
        return list.length == 0 ? -1 : list[0];
    }

    /**
     * LeafiaCpStandard.format: c = the component's route guidance (DiPO e/c), facts = LeafiaCpStandard.facts
     * ({maneuver type, driving side, junction, exit angle, angle known, route guidance state, metres}), meters = this
     * update's distance to the maneuver (-1 when the update did not carry item 10).
     */
    public static synchronized int cp(Object c, int[] facts, int meters) {
        try {
            if (c == null || facts == null || facts.length < 6) return meters;
            Cp s = CP.get(c);
            if (s == null) {
                if (CP.size() >= MAX_TRACKED) CP.clear();
                s = new Cp();
                CP.put(c, s);
            }
            if (facts[5] != ROUTE_SET) {   // arrived, loading, locating, rerouting, proceed to route: a new start
                s.forget();
                return meters;
            }
            if (meters < 0) return meters;   // no distance in this update: Leafia's far layout, nothing learnt
            return cpTake(s, index(c), facts[0], meters, now());
        } catch (Throwable t) {
            return meters;
        }
    }

    static int cpTake(Cp s, int index, int type, int meters, long t) {
        boolean newKey = !s.keyed || s.index != index || s.type != type;
        boolean turnChanged = !s.keyed || s.index != index;
        boolean jumpPending = s.jump >= 0;
        s.jump = -1;
        boolean riseRecent = s.rose && t - s.roseAt <= RISE_MS;
        // put-off: the new turn's first distance is the previous turn's last one (once per turn)
        if (newKey && turnChanged && !jumpPending && !riseRecent && s.last >= 0 && meters == s.last
                && !(s.putOff && s.putOffIndex == index && s.putOffType == type)) {
            s.putOff = true;
            s.putOffIndex = index;
            s.putOffType = type;
            return -1;
        }
        // jump-hold: the same turn's distance jumps up and would be near on its own: the frame as before, once (a
        // jump to the far side goes out at once: far is right for it)
        if (!newKey && !jumpPending && s.last >= 0
                && ((s.last <= PASS_NEAR && meters > s.last + PASS_RISE) || meters > s.last + NEW_TURN_JUMP)
                && meters <= WINDOW) {
            s.jump = meters;
            return s.shown;
        }
        // another turn, a held jump taken or a jump: the hysteresis starts over
        if (newKey || jumpPending || meters > s.last + NEW_TURN_JUMP) s.on[0] = false;
        s.putOff = false;
        if (newKey || jumpPending || meters != s.last) {
            s.rose = !newKey && (jumpPending || (s.last >= 0 && meters >= s.last + RISE_MIN));
            if (s.rose) s.roseAt = t;
        }
        s.keyed = true;
        s.index = index;
        s.type = type;
        s.last = meters;
        s.shown = window(s.on, meters);
        return s.shown;
    }

    /** LeafiaCpStandard.routeReset: the component's route guidance was cleared */
    public static synchronized void cpForget(Object c) {
        try {
            Cp s = CP.get(c);
            if (s != null) s.forget();
        } catch (Throwable t) {
            // nothing
        }
    }
}
