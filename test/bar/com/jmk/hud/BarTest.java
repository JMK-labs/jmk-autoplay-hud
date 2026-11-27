package com.jmk.hud;

import java.lang.reflect.Field;

/**
 * jmk-autoplay-hud 0.1.33: src/tbt/bar/com/jmk/hud/Bar.java and Near.java (extended to the stock D) on the Mac JVM
 * (test/check-scripts.sh runs it). BarOut and NaviBar are Android glue and are not loaded here; their hooks are checked
 * on the disassembly. The Near cases are test/near's, with D = 350 m (1050 m for an expressway turn) in place of 457 m.
 */
public final class BarTest {
    static int ok, bad;

    static void eq(String what, int want, int got) {
        if (want == got) {
            ok++;
        } else {
            bad++;
            System.out.println("FAIL  " + what + ": want " + want + ", got " + got);
        }
    }

    static void is(String what, boolean cond) {
        eq(what, 1, cond ? 1 : 0);
    }

    static void bar(String what, Integer want, Integer got) {
        is(what + " (want " + want + ", got " + got + ")", want == null ? got == null : want.equals(got));
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

    /** what Leafia's LeafiaStandard.bar computes with the window d (the smali: m x 10 / d, 1..9, x 10; far: 0) */
    static int leafiaBar(int m, int d) {
        if (m < 0 || m > d) return 0;
        return Math.max(1, Math.min(9, m * 10 / d)) * 10;
    }

    /** the trap-info object form: every instance field a public int */
    public static final class Info {
        public int a, barGraphLevel, z;
        public static int unrelated = 7;
    }

    public static final class InfoFinal {
        public final int barGraphLevel = 0;
    }

    public static final class InfoNotInt {
        public int barGraphLevel;
        public long extra;
    }

    public static void main(String[] args) throws Exception {
        Near.clock = 1000;
        // ---------------------------------------------------------------- D
        eq("D: Android Auto general event", 350, Near.aaD(4));
        eq("D: Android Auto OFF_RAMP", 1050, Near.aaD(8));
        eq("D: Android Auto ON_RAMP stays general", 350, Near.aaD(7));
        for (int t : new int[] { 8, 22, 23, 51, 52, 53 }) eq("D: CarPlay expressway type " + t, 1050, Near.cpD(t));
        for (int t : new int[] { 0, 1, 2, 3, 4, 6, 7, 9, 13, 21, 24, 50, 54 }) eq("D: CarPlay general type " + t, 350, Near.cpD(t));
        eq("D: window() before any turn is D general", 350, Near.window());
        // the bar Leafia's formula gives with D (m x 10 / D, 1..9)
        eq("bar: D 350, 350 m", 90, leafiaBar(350, 350));
        eq("bar: D 350, 349 m", 90, leafiaBar(349, 350));
        eq("bar: D 350, 315 m", 90, leafiaBar(315, 350));
        eq("bar: D 350, 314 m", 80, leafiaBar(314, 350));
        eq("bar: D 350, 175 m", 50, leafiaBar(175, 350));
        eq("bar: D 350, 35 m", 10, leafiaBar(35, 350));
        eq("bar: D 350, 34 m (0 -> 1)", 10, leafiaBar(34, 350));
        eq("bar: D 350, 0 m", 10, leafiaBar(0, 350));
        eq("bar: D 350, 351 m far", 0, leafiaBar(351, 350));
        eq("bar: D 1050, 1050 m", 90, leafiaBar(1050, 1050));
        eq("bar: D 1050, 525 m", 50, leafiaBar(525, 1050));
        eq("bar: D 1050, 105 m", 10, leafiaBar(105, 1050));

        // ---------------------------------------------------------------- Android Auto: window and hysteresis
        Near.aaForget();
        eq("aa: far above D", 600, Near.aa(4, 2, 600));
        eq("aa: 360 still far (never near)", 360, Near.aa(4, 2, 360));
        eq("aa: window is 350", 350, Near.window());
        eq("aa: 350 near", 350, Near.aa(4, 2, 350));
        eq("aa: 360 stays near (full bar: D)", 350, Near.aa(4, 2, 360));
        eq("aa: 400 stays near", 350, Near.aa(4, 2, 400));
        eq("aa: 401 goes far", 401, Near.aa(4, 2, 401));
        eq("aa: 380 after going far stays far", 380, Near.aa(4, 2, 380));
        eq("aa: 300 near", 300, Near.aa(4, 2, 300));
        eq("aa: -1 (no distance yet) as it came", -1, Near.aa(4, 2, -1));
        eq("aa: another turn (side) at 380 is far", 380, Near.aa(4, 1, 380));
        eq("aa: 340 near", 340, Near.aa(4, 1, 340));
        eq("aa: another event at 360 is far", 360, Near.aa(5, 1, 360));
        eq("aa: 20 near", 20, Near.aa(5, 1, 20));
        eq("aa: same shape, distance up by more than 100 (next turn) at 360: far", 360, Near.aa(5, 1, 360));
        Near.aaForget();
        eq("aa: after the reset 380 is far", 380, Near.aa(5, 1, 380));
        // expressway (OFF_RAMP): D 1050
        Near.aaForget();
        eq("aa ramp: 1100 far", 1100, Near.aa(8, 2, 1100));
        eq("aa ramp: window is 1050", 1050, Near.window());
        eq("aa ramp: 1050 near", 1050, Near.aa(8, 2, 1050));
        eq("aa ramp: 1100 stays near (D + 50)", 1050, Near.aa(8, 2, 1100));
        eq("aa ramp: 1101 goes far", 1101, Near.aa(8, 2, 1101));
        eq("aa ramp: 700 near", 700, Near.aa(8, 2, 700));
        eq("aa ramp: the next general turn at 500: far (350)", 500, Near.aa(4, 2, 500));
        eq("aa ramp: window back to 350", 350, Near.window());
        eq("aa: -1 sets D too", -1, Near.aa(8, 2, -1));
        eq("aa: window 1050 after an OFF_RAMP update without distance", 1050, Near.window());

        // ---------------------------------------------------------------- CarPlay: hysteresis
        Rg c = new Rg();
        eq("cp: 360 far", 360, cp(c, 3, 2, 360));
        eq("cp: window 350", 350, Near.window());
        eq("cp: 350 near", 350, cp(c, 3, 2, 350));
        eq("cp: 380 stays near", 350, cp(c, 3, 2, 380));
        eq("cp: 410 goes far", 410, cp(c, 3, 2, 410));
        eq("cp: 390 stays far", 390, cp(c, 3, 2, 390));
        eq("cp: no item 10 as it came", -1, cp(c, 3, 2, -1));
        eq("cp: 300 near", 300, cp(c, 3, 2, 300));
        // expressway exit (type 22): D 1050
        c = new Rg();
        eq("cp exit: 1100 far", 1100, cp(c, 3, 22, 1100));
        eq("cp exit: window 1050", 1050, Near.window());
        eq("cp exit: 1050 near", 1050, cp(c, 3, 22, 1050));
        eq("cp exit: 1090 stays near", 1050, cp(c, 3, 22, 1090));
        eq("cp exit: 1101 goes far", 1101, cp(c, 3, 22, 1101));
        eq("cp exit: 900 near", 900, cp(c, 3, 22, 900));
        // the next turn is a general one: D 350 again, hysteresis starts over
        eq("cp exit: next turn (type 2) at 600: far", 600, cp(c, 4, 2, 600));
        eq("cp exit: window 350 again", 350, Near.window());
        eq("cp exit: 340 near", 340, cp(c, 4, 2, 340));
        // an exit type with the turn type changing at the same index starts over too
        eq("cp exit: same index, now a general type at 900: far", 900, cp(c, 4, 22, 900));

        // ---------------------------------------------------------------- CarPlay: Naver Map (put-off)
        c = new Rg();
        cp(c, 5, 2, 200);
        cp(c, 5, 2, 60);
        eq("naver: last distance of turn 5", 17, cp(c, 5, 2, 17));
        eq("naver: turn 6 with turn 5's 17 m: put off (far)", -1, cp(c, 6, 13, 17));
        eq("naver: turn 6's own distance 640: far", 640, cp(c, 6, 13, 640));
        eq("naver: turn 6 at 340: near", 340, cp(c, 6, 13, 340));
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
        // the window of a jump is the turn's D: 300 m is inside 350 (held), 360 m is far at once
        c = new Rg();
        cp(c, 2, 2, 90);
        cp(c, 2, 2, 6);
        eq("kakao D: a jump to 360 m (outside 350) goes out at once", 360, cp(c, 2, 2, 360));
        // an expressway turn holds a jump up to 1050
        c = new Rg();
        cp(c, 2, 22, 900);
        cp(c, 2, 22, 6);
        eq("kakao D: a jump to 900 m on an exit turn (inside 1050) is held", 6, cp(c, 2, 22, 900));

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

        // ---------------------------------------------------------------- what is sent: aaBar / cpBar
        eq("aaBar: no result", Bar.NONE, Bar.aaBar(null));
        eq("aaBar: short result", Bar.NONE, Bar.aaBar(new int[] { 1, 2 }));
        eq("aaBar: near bar", 40, Bar.aaBar(new int[] { 0x21, 90, 40, 0xffff }));
        eq("aaBar: far (0)", 0, Bar.aaBar(new int[] { 0x21, 90, 0, 0xffff }));
        eq("aaBar: full (90)", 90, Bar.aaBar(new int[] { 0x21, 90, 90, 0xffff }));
        eq("aaBar: out of range", Bar.NONE, Bar.aaBar(new int[] { 0, 0, 101, 0 }));
        eq("aaBar: negative", Bar.NONE, Bar.aaBar(new int[] { 0, 0, -3, 0 }));
        eq("cpBar: near", 70, Bar.cpBar(0x11, 70));
        eq("cpBar: far (0)", 0, Bar.cpBar(0x21, 0));
        eq("cpBar: display type 8 (nothing to show)", Bar.NONE, Bar.cpBar(8, 50));
        eq("cpBar: out of range", Bar.NONE, Bar.cpBar(0x11, 150));

        // ---------------------------------------------------------------- Sender
        Bar.Sender s = new Bar.Sender();
        is("sender: first value goes", s.due(50, 0L));
        is("sender: the same value is not sent again", !s.due(50, 9999L));
        is("sender: the same value goes again after 10 s", s.due(50, 10000L));
        is("sender: a changed value goes at once", s.due(60, 10001L));
        is("sender: NONE goes once", s.due(Bar.NONE, 10002L));
        is("sender: NONE is never repeated", !s.due(Bar.NONE, 99999L));
        is("sender: 0 (far) is sent like a value", s.due(0, 100000L) && !s.due(0, 100001L) && s.due(0, 110000L));
        eq("constants: resend 10 s", 10000, (int) Bar.RESEND_MS);
        eq("constants: expire 3 min", 180000, (int) Bar.EXPIRE_MS);

        // ---------------------------------------------------------------- Navi decisions
        Bar.Navi n = new Bar.Navi();
        bar("navi: a broadcast before any stock frame sends nothing (never invents cameras)", null, n.onBar(50, true, 100L));
        eq("navi: the first stock frame, the phone's bar wins", 50, n.onStock(30, true, 200L));
        is("navi: overriding", n.isOverriding());
        eq("navi: current is the phone's", 50, n.current());
        bar("navi: the same value again: nothing", null, n.onBar(50, true, 300L));
        bar("navi: a new value: sent again", 60, n.onBar(60, true, 400L));
        eq("navi: the next stock frame carries 60", 60, n.onStock(30, true, 500L));
        bar("navi: NONE: the stock bar goes back", 30, n.onBar(Bar.NONE, true, 600L));
        is("navi: not overriding", !n.isOverriding());
        bar("navi: NONE again: nothing", null, n.onBar(Bar.NONE, true, 700L));
        eq("navi: the stock frame passes as it is", 25, n.onStock(25, true, 800L));
        bar("navi: a bar while the phone is not guiding: stays stock", null, n.onBar(40, false, 900L));
        eq("navi: stock frame, phone not guiding", 25, n.onStock(25, false, 950L));
        bar("navi: phone guiding again, a bar: sent", 40, n.onBar(40, true, 1000L));
        bar("navi: a tick while live: nothing", null, n.check(true, 1000L + Bar.EXPIRE_MS - 1));
        bar("navi: a tick after the expiry: stock bar back", 25, n.check(true, 1000L + Bar.EXPIRE_MS));
        eq("navi: after the expiry a stock frame is stock", 20, n.onStock(20, true, 1000L + Bar.EXPIRE_MS + 1));
        bar("navi: the phone stops guiding (tick): back to stock", null, n.check(false, 2000L + Bar.EXPIRE_MS));
        bar("navi: a bar, then the phone stops guiding: tick restores", 20, new Func().run());
        bar("navi: a bar out of range is none", null, outOfRange());
        bar("navi: a bar of 0 (far) is a bar", 0, zeroBar());

        // ---------------------------------------------------------------- trap-info arguments
        Object[] a17 = new Object[17];
        for (int i = 0; i < 17; i++) a17[i] = Integer.valueOf(i + 100);
        a17[Bar.BAR_ARG] = Integer.valueOf(40);
        eq("args: 17-int bar", 40, Bar.intBar(a17));
        a17[Bar.BAR_ARG] = Integer.valueOf(101);
        eq("args: 17-int bar out of range", -1, Bar.intBar(a17));
        eq("args: 16 ints", -1, Bar.intBar(new Object[16]));
        eq("args: null", -1, Bar.intBar(null));
        a17[Bar.BAR_ARG] = Integer.valueOf(40);
        Object[] w = Bar.withBar(a17, false, null, 70);
        eq("args: withBar sets only the bar", 70, (Integer) w[Bar.BAR_ARG]);
        is("args: withBar leaves the others", (Integer) w[0] == 100 && (Integer) w[16] == 116 && (Integer) w[10] == 110);
        eq("args: withBar does not touch the stock array", 40, (Integer) a17[Bar.BAR_ARG]);
        Field f = Bar.barField(Info.class);
        is("args: barGraphLevel found in an all-int object", f != null && f.getName().equals("barGraphLevel"));
        is("args: a final field refuses the copy", Bar.barField(InfoFinal.class) == null);
        is("args: a non-int field refuses the copy", Bar.barField(InfoNotInt.class) == null);
        Info i0 = new Info();
        i0.a = 5;
        i0.barGraphLevel = 30;
        i0.z = 9;
        Object[] wi = Bar.withBar(new Object[] { i0 }, true, f, 80);
        Info i1 = (Info) wi[0];
        is("args: object copy has the bar changed", i1.barGraphLevel == 80 && i1 != i0);
        is("args: object copy keeps the other fields", i1.a == 5 && i1.z == 9);
        eq("args: the stock object keeps its bar", 30, i0.barGraphLevel);

        System.out.println(bad == 0 ? "bar: all " + ok + " passed" : "bar: " + bad + " FAILED, " + ok + " passed");
        System.exit(bad == 0 ? 0 : 1);
    }

    static final class Func {
        Integer run() {
            Bar.Navi n = new Bar.Navi();
            n.onStock(20, true, 10L);
            n.onBar(40, true, 20L);
            return n.check(false, 30L);
        }
    }

    static Integer outOfRange() {
        Bar.Navi n = new Bar.Navi();
        n.onStock(20, true, 10L);
        return n.onBar(150, true, 20L);
    }

    static Integer zeroBar() {
        Bar.Navi n = new Bar.Navi();
        n.onStock(20, true, 10L);
        return n.onBar(0, true, 20L);
    }
}
