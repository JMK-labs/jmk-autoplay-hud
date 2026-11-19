package com.jmk.hud;

/**
 * jmk-autoplay-hud 0.1.11: src/tbt/com/jmk/hud/Near.java on the Mac JVM (test/check-scripts.sh runs it). The CarPlay
 * sequences are the ones Korea Projection 1.7.4 documents from car logs (Naver Map: issue 76, transitions 15/15, 0/0,
 * 17/17; KakaoNavi: Niro 2026-11-15, the next distance on the old index 30-130 ms before the new index, 6@485).
 */
public final class NearTest {
    static int ok, bad;

    static void eq(String what, int want, int got) {
        if (want == got) {
            ok++;
        } else {
            bad++;
            System.out.println("FAIL  " + what + ": want " + want + ", got " + got);
        }
    }

    /** DiPO's route guidance object as Near reads it: the current maneuver list in field bd */
    static final class Rg {
        int[] bd = { 0 };
    }

    static final class NoBd {
    }

    static int[] facts(int type, int state) {
        return new int[] { type, 0, 0, 0, 1, state, -1 };
    }

    static int cp(Rg c, int index, int type, int meters) {
        c.bd = new int[] { index, index + 1 };
        Near.clock += 100;
        return Near.cp(c, facts(type, 1), meters);
    }

    public static void main(String[] a) {
        Near.clock = 1000;
        // ---------------------------------------------------------------- Android Auto: window and hysteresis
        Near.aaForget();
        eq("aa: far above the window", 600, Near.aa(4, 2, 600));
        eq("aa: 470 still far (never near)", 470, Near.aa(4, 2, 470));
        eq("aa: 457 near", 457, Near.aa(4, 2, 457));
        eq("aa: 460 stays near (full bar: 457)", 457, Near.aa(4, 2, 460));
        eq("aa: 507 stays near", 457, Near.aa(4, 2, 507));
        eq("aa: 508 goes far", 508, Near.aa(4, 2, 508));
        eq("aa: 480 after going far stays far", 480, Near.aa(4, 2, 480));
        eq("aa: 300 near", 300, Near.aa(4, 2, 300));
        eq("aa: -1 (no distance yet) as it came", -1, Near.aa(4, 2, -1));
        eq("aa: another turn (side) at 480 is far", 480, Near.aa(4, 1, 480));
        eq("aa: 450 near", 450, Near.aa(4, 1, 450));
        eq("aa: another event at 470 is far", 470, Near.aa(5, 1, 470));
        eq("aa: 20 near", 20, Near.aa(5, 1, 20));
        eq("aa: same shape, distance up by more than 100 (next turn) at 470: far", 470, Near.aa(5, 1, 470));
        Near.aa(5, 1, 400);
        Near.aaForget();
        eq("aa: after the reset 480 is far", 480, Near.aa(5, 1, 480));

        // ---------------------------------------------------------------- CarPlay: hysteresis
        Rg c = new Rg();
        eq("cp: 470 far", 470, cp(c, 3, 2, 470));
        eq("cp: 457 near", 457, cp(c, 3, 2, 457));
        eq("cp: 480 stays near", 457, cp(c, 3, 2, 480));
        eq("cp: 510 goes far", 510, cp(c, 3, 2, 510));
        eq("cp: 490 stays far", 490, cp(c, 3, 2, 490));
        eq("cp: no item 10 as it came", -1, cp(c, 3, 2, -1));
        eq("cp: 400 near", 400, cp(c, 3, 2, 400));

        // ---------------------------------------------------------------- CarPlay: Naver Map (put-off)
        c = new Rg();
        cp(c, 5, 2, 200);
        cp(c, 5, 2, 60);
        eq("naver: last distance of turn 5", 17, cp(c, 5, 2, 17));
        eq("naver: turn 6 with turn 5's 17 m: put off (far)", -1, cp(c, 6, 13, 17));
        eq("naver: turn 6's own distance 640: far", 640, cp(c, 6, 13, 640));
        eq("naver: turn 6 at 450: near", 450, cp(c, 6, 13, 450));
        cp(c, 6, 13, 15);
        eq("naver: turn 7 with 15: put off", -1, cp(c, 7, 1, 15));
        eq("naver: turn 7 with 15 again (really that close): taken", 15, cp(c, 7, 1, 15));
        cp(c, 7, 1, 0);
        eq("naver: turn 8 with 0: put off", -1, cp(c, 8, 2, 0));
        eq("naver: turn 8 at 120: near", 120, cp(c, 8, 2, 120));
        eq("naver: a different distance on a new turn is taken (18@40 -> 21@35)", 35, cp(c, 9, 2, 35));
        eq("naver: no item 10 on the next turn: as it came", -1, cp(c, 10, 2, -1));

        // ---------------------------------------------------------------- CarPlay: KakaoNavi (jump-hold)
        c = new Rg();
        cp(c, 2, 2, 90);
        eq("kakao: turn 2 at 6 m", 6, cp(c, 2, 2, 6));
        eq("kakao: turn 3's 300 m on turn 2's index: held (turn 2's frame again)", 6, cp(c, 2, 2, 300));
        eq("kakao: turn 3 with 300: taken, no put-off", 300, cp(c, 3, 1, 300));
        eq("kakao: turn 3 at 280", 280, cp(c, 3, 1, 280));
        cp(c, 3, 1, 6);
        eq("kakao: turn 4's 485 m on turn 3's index: far at once (not held)", 485, cp(c, 3, 1, 485));
        eq("kakao: turn 4 with 485: far", 485, cp(c, 4, 2, 485));
        cp(c, 4, 2, 25);
        eq("kakao: near next turn 40 m on the old index (passed: up by 15 from 25): not held, taken", 40, cp(c, 4, 2, 40));
        eq("kakao: turn 5 with the same 40 m right after the rise: no put-off", 40, cp(c, 5, 2, 40));
        cp(c, 5, 2, 8);
        eq("kakao: rise 8 -> 35 (passed): held", 8, cp(c, 5, 2, 35));
        eq("kakao: no new index came: the held distance is taken on the same turn", 35, cp(c, 5, 2, 35));

        // ---------------------------------------------------------------- CarPlay: route state and reset
        c = new Rg();
        cp(c, 1, 2, 12);
        eq("state: rerouting (5) forgets, metres as they came", 12, Near.cp(c, facts(2, 5), 12));
        c.bd = new int[] { 0 };
        eq("state: the new route's first turn with the same 12 m is not put off", 12, Near.cp(c, facts(2, 1), 12));
        cp(c, 4, 2, 9);
        Near.cpForget(c);
        eq("reset: after routeReset the next turn with 9 is not put off", 9, cp(c, 5, 2, 9));
        eq("bad input: no facts", 33, Near.cp(c, null, 33));
        eq("bad input: an object without bd gives the metres back", 77, Near.cp(new NoBd(), facts(2, 1), 77));
        eq("bad input: null route guidance", 55, Near.cp(null, facts(2, 1), 55));

        System.out.println(bad == 0 ? "near: all " + ok + " passed" : "near: " + bad + " FAILED, " + ok + " passed");
        System.exit(bad == 0 ? 0 : 1);
    }
}
