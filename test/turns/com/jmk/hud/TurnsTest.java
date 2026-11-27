package com.jmk.hud;

/**
 * jmk-autoplay-hud 0.1.34: src/tbt/turns/com/jmk/hud/Turns.java on the Mac JVM (test/check-scripts.sh runs it).
 * TurnsOut is Android glue and is not loaded here; its hooks are checked on the disassembly.
 *
 * Every row of the mapping: "before" is what the 0.1.33 build (Leafia's turn code) gave, read from its disassembly
 * (GpmNaviTBTManager.setRampDisplayType, LeafiaStandard.format, DiPO e/u's table, u.leafiaSimpleManeuver,
 * LeafiaCpStandard.nativeTurn / projection); "after" is what Turns gives.
 */
public final class TurnsTest {
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

    static void str(String what, String want, String got) {
        is(what + " (want \"" + want + "\", got \"" + got + "\")", want.equals(got));
    }

    static void arr(String what, int[] want, int[] got) {
        is(what + " (want " + java.util.Arrays.toString(want) + ", got " + java.util.Arrays.toString(got) + ")",
                java.util.Arrays.equals(want, got));
    }

    static final int L = Turns.LEFT, R = Turns.RIGHT, NONE = 3;

    /**
     * Android Auto, far: {event, side, before, after}. The events the ramp method does not handle never reach the
     * hook; their numbers pass through all the same.
     */
    static final int[][] AA_FAR = {
        { 7, R, 173, 161 }, { 7, L, 174, 162 }, { 7, NONE, 172, 160 },        // ON_RAMP
        { 8, R, 81, 164 }, { 8, L, 82, 165 }, { 8, NONE, 86, 163 },           // OFF_RAMP
        { 9, R, 173, 173 }, { 9, L, 174, 174 },                               // FORK: as before
        { 16, NONE, 176, 176 },                                               // FERRY_BOAT
        { 3, R, 66, 66 }, { 3, L, 71, 71 }, { 4, R, 67, 67 }, { 4, L, 70, 70 }, { 5, R, 68, 68 }, { 5, L, 69, 69 },
        { 2, NONE, 65, 65 }, { 14, NONE, 65, 65 }, { 10, NONE, 65, 65 }, { 6, L, 72, 72 }, { 6, R, 73, 73 },
        { 13, R, 99, 99 }, { 12, R, 32, 32 }, { 19, NONE, 112, 112 },
        { 7, R, 81, 81 }, { 8, R, 173, 173 },                                 // a number of the other ramp kind: left alone
    };

    /**
     * Android Auto, near, at 200 m of D 350 (bar 50): {event, side, before display, before degrees, after display,
     * after degrees x 10, after side-street bits}; before -1: none (the far picture stayed); after display -1: Turns
     * gives null (Leafia's layout, the "before" columns, stays).
     */
    static final int[][] AA_NEAR = {
        { 7, R, -1, 0, 13, 450, 0 }, { 7, L, -1, 0, 13, 3150, 0 }, { 7, NONE, -1, 0, 13, 0, 0 },      // ON_RAMP
        { 9, R, 25, 90, 13, 225, 3 }, { 9, L, 25, 270, 13, 3375, 16386 }, { 9, NONE, -1, 0, -1, 0, 0 }, // FORK
        { 3, R, 13, 45, -1, 0, 0 }, { 3, L, 13, 315, -1, 0, 0 },
        { 4, R, 13, 90, -1, 0, 0 }, { 4, L, 13, 270, -1, 0, 0 },
        { 5, R, 13, 135, -1, 0, 0 }, { 5, L, 13, 225, -1, 0, 0 },
        { 2, R, 13, 90, -1, 0, 0 }, { 2, L, 13, 270, -1, 0, 0 }, { 2, NONE, 13, 0, -1, 0, 0 },
        { 14, NONE, 13, 0, -1, 0, 0 }, { 10, NONE, 13, 0, -1, 0, 0 },
        { 6, L, 31, 270, -1, 0, 0 }, { 6, R, 31, 90, -1, 0, 0 },
        { 8, R, 17, 90, -1, 0, 0 }, { 8, L, 18, 270, -1, 0, 0 }, { 8, NONE, -1, 0, -1, 0, 0 },
        { 12, R, 32, 0, -1, 0, 0 }, { 13, L, 33, 0, -1, 0, 0 }, { 16, NONE, -1, 0, -1, 0, 0 }, { 19, NONE, 112, 0, -1, 0, 0 },
        { 11, NONE, -1, 0, -1, 0, 0 },
    };

    /**
     * CarPlay, far: {type, side, junction, exit, known, state, table (before: the build's table / simple rows, 0 none),
     * leafia (before: after Leafia's projection; 0 = nothing sent, the old arrow stayed), after}, and the rule.
     */
    static final Object[][] CP_FAR = {
        // left / right turns
        { 1, 0, 0, 0, 0, 1, 70, 70, 70, "table" },
        { 1, 0, 0, -45, 1, 1, 145, 145, 145, "table" },
        { 1, 0, 0, -60, 1, 1, 71, 71, 71, "table" },
        { 1, 0, 0, -90, 1, 1, 70, 70, 70, "table" },
        { 1, 0, 0, -120, 1, 1, 69, 69, 69, "table" },
        { 1, 0, 0, -30, 1, 1, 0, 70, 71, "band" },
        { 1, 0, 0, -67, 1, 1, 0, 70, 71, "band" },
        { 1, 0, 0, -75, 1, 1, 0, 70, 70, "band" },
        { 1, 0, 0, -112, 1, 1, 0, 70, 70, "band" },
        { 1, 0, 0, -130, 1, 1, 0, 70, 69, "band" },
        { 1, 0, 0, 30, 1, 1, 0, 0, 71, "band" },            // an angle on the other side: Leafia gave nothing
        { 1, 0, 0, 330, 1, 1, 0, 70, 71, "band" },          // the same angle as 0..359
        { 2, 0, 0, 0, 0, 1, 67, 67, 67, "table" },
        { 2, 0, 0, 45, 1, 1, 144, 144, 144, "table" },
        { 2, 0, 0, 60, 1, 1, 66, 66, 66, "table" },
        { 2, 0, 0, 120, 1, 1, 68, 68, 68, "table" },
        { 2, 0, 0, 30, 1, 1, 0, 67, 66, "band" },
        { 2, 0, 0, 100, 1, 1, 0, 67, 67, "band" },
        { 2, 0, 0, 150, 1, 1, 0, 67, 68, "band" },
        // slight / sharp
        { 49, 0, 0, 0, 0, 1, 71, 71, 71, "table" }, { 50, 0, 0, 0, 0, 1, 66, 66, 66, "table" },
        { 49, 0, 0, -45, 1, 1, 71, 71, 71, "table" }, { 50, 0, 0, 45, 1, 1, 66, 66, 66, "table" },
        { 49, 0, 0, -20, 1, 1, 0, 71, 71, "band" }, { 50, 0, 0, 20, 1, 1, 0, 66, 66, "band" },
        { 49, 0, 0, -80, 1, 1, 0, 0, 71, "band" }, { 50, 0, 0, 80, 1, 1, 0, 0, 66, "band" },
        { 47, 0, 0, 0, 0, 1, 0, 69, 69, "leafia" }, { 48, 0, 0, 0, 0, 1, 0, 68, 68, "leafia" },
        { 47, 0, 0, -140, 1, 1, 69, 69, 69, "table" }, { 48, 0, 0, 140, 1, 1, 68, 68, 68, "table" },
        { 47, 0, 0, -100, 1, 1, 0, 0, 69, "band" }, { 48, 0, 0, 100, 1, 1, 0, 0, 68, "band" },
        { 47, 0, 0, -160, 1, 1, 0, 69, 69, "band" }, { 48, 0, 0, 160, 1, 1, 0, 68, 68, "band" },
        // straight, follow road, U-turns, end of road
        { 3, 0, 0, 0, 0, 1, 65, 65, 65, "table" }, { 5, 0, 0, 0, 0, 1, 172, 172, 172, "table" },
        { 4, 0, 0, 0, 0, 1, 72, 72, 72, "table" }, { 4, 1, 0, 0, 0, 1, 73, 73, 73, "table" },
        { 18, 0, 0, 0, 0, 1, 0, 72, 72, "leafia" }, { 26, 0, 0, 0, 0, 1, 0, 72, 72, "leafia" },
        { 20, 0, 0, 0, 0, 1, 0, 70, 70, "leafia" }, { 21, 0, 0, 0, 0, 1, 0, 67, 67, "leafia" },
        // ramps: the stock numbers
        { 9, 0, 0, 0, 0, 1, 172, 172, 160, "stock" },
        { 9, 0, 0, 20, 1, 1, 0, 0, 160, "kp-fallback" },
        { 9, 1, 0, 0, 0, 1, 0, 0, 160, "kp-fallback" },
        { 22, 0, 0, 0, 0, 1, 82, 82, 165, "stock" }, { 23, 0, 0, 0, 0, 1, 81, 81, 164, "stock" },
        { 22, 1, 0, 0, 0, 1, 0, 82, 165, "gap" }, { 23, 1, 0, 0, 0, 1, 0, 81, 164, "gap" },
        { 22, 0, 0, -30, 1, 1, 0, 82, 165, "gap" }, { 23, 0, 0, 30, 1, 1, 0, 81, 164, "gap" },
        { 8, 0, 0, 40, 1, 1, 0, 81, 164, "gap" }, { 8, 0, 0, -40, 1, 1, 0, 82, 165, "gap" },
        { 8, 0, 0, 0, 0, 1, 0, 0, 163, "kp-fallback" },
        { 51, 0, 0, 0, 0, 1, 0, 0, 163, "kp-fallback" }, { 51, 0, 0, 30, 1, 1, 0, 0, 163, "kp-fallback" },
        { 52, 0, 0, 0, 0, 1, 174, 174, 174, "table" }, { 53, 0, 0, 0, 0, 1, 173, 173, 173, "table" },
        { 52, 0, 0, -20, 1, 1, 0, 0, 65, "kp-fallback" },   // off the stock row with a small angle: straight by the angle
        // keep left / right
        { 13, 0, 0, 0, 0, 1, 0, 174, 71, "gap" }, { 14, 0, 0, 0, 0, 1, 0, 173, 66, "gap" },
        { 13, 0, 0, -20, 1, 1, 0, 174, 71, "gap" }, { 14, 0, 0, 20, 1, 1, 0, 173, 66, "gap" },
        { 13, 0, 0, 30, 1, 1, 0, 0, 71, "kp-fallback" },    // an angle on the other side: Leafia gave nothing
        // roundabouts
        { 29, 0, 1, 90, 1, 1, 99, 99, 99, "table" }, { 31, 0, 1, 0, 0, 1, 97, 97, 97, "table" },
        { 2, 0, 1, 0, 0, 1, 96, 96, 96, "table" },
        { 31, 1, 1, 0, 0, 1, 96, 96, 192, "stock" },
        { 2, 1, 1, 0, 0, 1, 97, 97, 193, "stock" }, { 2, 1, 1, 90, 1, 1, 99, 99, 195, "stock" },
        { 2, 1, 1, 120, 1, 1, 100, 100, 196, "stock" }, { 2, 1, 1, 180, 1, 1, 102, 102, 198, "stock" },
        { 1, 1, 1, -120, 1, 1, 104, 104, 200, "stock" }, { 1, 1, 1, -90, 1, 1, 105, 105, 201, "stock" },
        { 1, 1, 1, -30, 1, 1, 107, 107, 203, "stock" },
        { 30, 0, 1, 45, 1, 1, 0, 97, 97, "leafia" },
        { 6, 0, 0, 0, 0, 1, 0, 0, 96, "kp-fallback" }, { 6, 1, 0, 0, 0, 1, 0, 0, 97, "kp-fallback" },
        { 6, 0, 1, 90, 1, 1, 0, 0, 99, "kp-fallback" }, { 6, 0, 1, -100, 1, 1, 0, 0, 105, "kp-fallback" },
        { 7, 0, 0, 0, 0, 1, 0, 0, 8, "kp-fallback" }, { 7, 0, 1, 0, 0, 1, 0, 0, 8, "kp-fallback" },
        // destination, start, ferry, unknown
        { 12, 0, 0, 0, 0, 1, 112, 112, 112, "table" }, { 24, 0, 0, 0, 0, 1, 114, 114, 114, "table" },
        { 25, 0, 0, 0, 0, 1, 113, 113, 113, "table" },
        { 12, 1, 0, 0, 0, 1, 0, 112, 112, "leafia" },
        { 10, 0, 0, 0, 0, 1, 0, 0, 112, "kp-fallback" }, { 27, 0, 0, 0, 0, 1, 0, 0, 112, "kp-fallback" },
        { 12, 0, 0, 0, 0, 2, 0, 3, 3, "leafia" }, { 1, 0, 0, -30, 1, 2, 0, 3, 3, "leafia" },
        { 11, 0, 0, 0, 0, 1, 0, 0, 8, "kp-fallback" }, { 11, 0, 0, 90, 1, 1, 0, 0, 8, "kp-fallback" },
        { 15, 0, 0, 0, 0, 1, 176, 176, 176, "table" },
        { 16, 0, 0, 0, 0, 1, 0, 0, 176, "kp-fallback" }, { 17, 0, 0, 0, 0, 1, 0, 0, 176, "kp-fallback" },
        { 0, 0, 0, 0, 0, 1, 0, 0, 8, "kp-fallback" }, { 60, 0, 0, 0, 0, 1, 0, 0, 8, "kp-fallback" },
        { 60, 0, 0, -100, 1, 1, 0, 0, 70, "kp-fallback" }, { 60, 0, 0, 40, 1, 1, 0, 0, 66, "kp-fallback" },
        { 60, 0, 0, 170, 1, 1, 0, 0, 72, "kp-fallback" }, { 60, 0, 0, 10, 1, 1, 0, 0, 65, "kp-fallback" },
        { 26, 1, 0, 0, 0, 1, 0, 0, 73, "kp-fallback" },
        { 60, 0, 0, -100, 0, 1, 0, 0, 8, "kp-fallback" },   // an angle the phone did not give is not used
    };

    /**
     * CarPlay, near: {type, side, junction, exit, known, state, before display (-1 none), before degrees, after
     * display (-1 none), after degrees}, and the rule. "before" is LeafiaCpStandard.nativeTurn's result.
     */
    static final Object[][] CP_NEAR = {
        { 9, 0, 0, 0, 0, 1, -1, 0, 13, 0, "near-onramp" },
        { 9, 0, 0, 30, 1, 1, -1, 0, 13, 30, "near-onramp" },
        { 9, 0, 0, -30, 1, 1, -1, 0, 13, 330, "near-onramp" },
        { 9, 0, 0, 180, 1, 1, -1, 0, 13, 0, "near-onramp" },
        { 9, 0, 0, 30, 0, 1, -1, 0, 13, 0, "near-onramp" },
        { 9, 0, 1, 0, 0, 1, -1, 0, -1, 0, "none" },
        { 9, 0, 0, 0, 0, 2, 3, 0, 3, 0, "leafia" },
        { 52, 0, 0, 0, 0, 1, -1, 0, 18, 270, "near-highway" },
        { 53, 0, 0, 0, 0, 1, -1, 0, 17, 90, "near-highway" },
        { 51, 0, 0, 0, 0, 1, -1, 0, 17, 90, "near-highway" },
        { 51, 0, 0, 25, 1, 1, -1, 0, 17, 90, "near-highway" },
        { 51, 0, 0, -25, 1, 1, -1, 0, 18, 270, "near-highway" },
        { 51, 1, 0, 0, 0, 1, -1, 0, 18, 270, "near-highway" },
        { 53, 0, 0, -25, 1, 1, -1, 0, 17, 90, "near-highway" },
        // as before
        { 8, 0, 0, 40, 1, 1, 17, 40, 17, 40, "leafia" }, { 8, 0, 0, -40, 1, 1, 18, 320, 18, 320, "leafia" },
        { 8, 0, 0, 0, 0, 1, -1, 0, -1, 0, "none" },
        { 22, 0, 0, 0, 0, 1, 18, 270, 18, 270, "leafia" }, { 23, 0, 0, 0, 0, 1, 17, 90, 17, 90, "leafia" },
        { 13, 0, 0, 0, 0, 1, 13, 315, 13, 315, "leafia" }, { 14, 0, 0, 0, 0, 1, 13, 45, 13, 45, "leafia" },
        { 1, 0, 0, 0, 0, 1, 13, 270, 13, 270, "leafia" }, { 2, 0, 0, 100, 1, 1, 13, 100, 13, 100, "leafia" },
        { 49, 0, 0, 0, 0, 1, 13, 315, 13, 315, "leafia" }, { 48, 0, 0, 0, 0, 1, 13, 135, 13, 135, "leafia" },
        { 3, 0, 0, 0, 0, 1, 13, 0, 13, 0, "leafia" }, { 4, 0, 0, 0, 0, 1, 31, 270, 31, 270, "leafia" },
        { 30, 0, 1, 45, 1, 1, 32, 45, 32, 45, "leafia" }, { 12, 0, 0, 0, 0, 1, 112, 0, 112, 0, "leafia" },
        { 6, 0, 0, 0, 0, 1, -1, 0, -1, 0, "none" }, { 11, 0, 0, 0, 0, 1, -1, 0, -1, 0, "none" },
        { 0, 0, 0, 0, 0, 1, -1, 0, -1, 0, "none" }, { 52, 0, 0, 0, 0, 2, 3, 0, 3, 0, "leafia" },
    };

    static int i(Object o) {
        return ((Integer) o).intValue();
    }

    public static void main(String[] a) {
        // ---------------------------------------------------------------- Android Auto, far
        for (int[] r : AA_FAR) {
            eq("aa far ev " + r[0] + " side " + r[1] + " before " + r[2], r[3], Turns.aaFar(r[0], r[1], r[2]));
            boolean ramp = (r[0] == 7 || r[0] == 8) && r[3] != r[2];
            str("aa far rule ev " + r[0] + " icon " + r[3], ramp ? "stock" : "leafia", Turns.aaFarRule(r[0], r[3]));
        }
        // ---------------------------------------------------------------- Android Auto, near
        for (int[] r : AA_NEAR) {
            String w = "aa near ev " + r[0] + " side " + r[1] + " (before " + (r[2] < 0 ? "none" : r[2] + " @" + r[3]) + ")";
            int[] got = Turns.aaNear(r[0], r[1], 200, 350);
            if (r[4] < 0) {
                is(w + ": Leafia's stays", got == null);
            } else {
                arr(w, new int[] { r[4], r[5] / 10, 50, r[6], r[5] }, got);
                eq(w + ": direction x 10 of the turn frame", r[5], Math.round(Turns.aaDir(got, 999f) * 10f));
                is(w + ": not what it was before", r[2] != r[4] || r[3] * 10 != r[5]);
            }
            is(w + ": far outside the window", Turns.aaNear(r[0], r[1], 351, 350) == null);
            is(w + ": no distance", Turns.aaNear(r[0], r[1], -1, 350) == null);
        }
        arr("aa near fork right at the window's edge", new int[] { 13, 22, 90, 3, 225 }, Turns.aaNear(9, R, 350, 350));
        arr("aa near fork left at 0 m", new int[] { 13, 337, 10, 16386, 3375 }, Turns.aaNear(9, L, 0, 350));
        arr("aa near on-ramp right, 34 m", new int[] { 13, 45, 10, 0, 450 }, Turns.aaNear(7, R, 34, 350));
        arr("aa near on-ramp left, 35 m", new int[] { 13, 315, 10, 0, 3150 }, Turns.aaNear(7, L, 35, 350));
        arr("aa near on-ramp, 70 m", new int[] { 13, 0, 20, 0, 0 }, Turns.aaNear(7, NONE, 70, 350));
        arr("aa near on-ramp, 349 m", new int[] { 13, 0, 90, 0, 0 }, Turns.aaNear(7, NONE, 349, 350));
        is("aa near with a window of 0", Turns.aaNear(7, R, 0, 0) != null && Turns.aaNear(7, R, 0, 0)[2] == 0);
        is("aa dir: fork right 22.5", Turns.aaDir(new int[] { 13, 22, 50, 3, 225 }, 22f) == 22.5f);
        is("aa dir: fork left 337.5", Turns.aaDir(new int[] { 13, 337, 50, 16386, 3375 }, 337f) == 337.5f);
        is("aa dir: Leafia's result (4 values) keeps its direction", Turns.aaDir(new int[] { 13, 90, 50, 0 }, 90f) == 90f);
        is("aa dir: no result keeps the far direction", Turns.aaDir(null, 30f) == 30f);
        str("aa near rule ours on-ramp", "near-onramp", Turns.aaNearRule(7, true));
        str("aa near rule ours fork", "near-fork", Turns.aaNearRule(9, true));
        str("aa near rule Leafia's", "leafia", Turns.aaNearRule(4, false));
        eq("bar 1050 m window, 1050 m", 90, Turns.bar(1050, 1050));
        eq("bar 1050 m window, 500 m", 40, Turns.bar(500, 1050));
        eq("bar 350 m window, 175 m", 50, Turns.bar(175, 350));

        // ---------------------------------------------------------------- CarPlay, far
        String[] why = new String[1];
        for (Object[] r : CP_FAR) {
            String w = "cp far type " + r[0] + " side " + r[1] + " junction " + r[2] + " exit " + (i(r[4]) != 0 ? r[3] : "none")
                    + " state " + r[5] + " (before " + (i(r[7]) == 0 ? "nothing" : r[7]) + ")";
            why[0] = null;
            eq(w, i(r[8]), Turns.cpFar(i(r[0]), i(r[1]), i(r[2]), i(r[3]), i(r[4]) != 0, i(r[5]), i(r[6]), i(r[7]), why));
            str(w + ": rule", (String) r[9], String.valueOf(why[0]));
            is(w + ": a table number is the number before", i(r[6]) == 0 || i(r[6]) == i(r[7]));
            is(w + ": never nothing", i(r[8]) != 0);
        }
        // every type, with and without an angle, where the build had nothing: a number comes out (0 never)
        for (int type = 0; type <= 70; type++) {
            for (int e = -180; e <= 180; e += 5) {
                for (int j = 0; j <= 1; j++) {
                    int f = Turns.cpFar(type, 0, j, e, e != 0, 1, 0, 0, why);
                    if (f == 0 || why[0] == null) is("cp far type " + type + " exit " + e + " junction " + j + " gives a number", false);
                }
            }
        }
        ok++;
        // a table number is only changed in the rows the build changed
        for (int type = 0; type <= 70; type++) {
            for (int icon = 1; icon <= 210; icon++) {
                int f = Turns.cpFar(type, 0, 0, 0, false, 1, icon, icon, why);
                boolean changed = (type == 9 && icon == 172) || (type == 22 && icon == 82) || (type == 23 && icon == 81);
                if ((f != icon) != changed) is("cp table number " + icon + " of type " + type + " (right-hand traffic) stays", false);
                int g = Turns.cpFar(type, 0, 1, 0, false, 1, icon, icon, why);
                if ((g != icon) != changed) is("cp table number " + icon + " of type " + type + " (roundabout, right-hand traffic) stays", false);
            }
        }
        ok++;
        eq("signed 315", -45, Turns.signed(315));
        eq("signed -180", 180, Turns.signed(-180));
        eq("signed 180", 180, Turns.signed(180));
        eq("signed 540", 180, Turns.signed(540));
        eq("signed -45", -45, Turns.signed(-45));

        // ---------------------------------------------------------------- CarPlay, near
        for (Object[] r : CP_NEAR) {
            String w = "cp near type " + r[0] + " side " + r[1] + " junction " + r[2] + " exit " + (i(r[4]) != 0 ? r[3] : "none")
                    + " state " + r[5] + " (before " + (i(r[6]) < 0 ? "none" : r[6] + " @" + r[7]) + ")";
            int[] before = i(r[6]) < 0 ? null : new int[] { i(r[6]), i(r[7]) };
            why[0] = null;
            int[] got = Turns.cpNear(before, i(r[0]), i(r[1]), i(r[2]), i(r[3]), i(r[4]) != 0, i(r[5]), why);
            if (i(r[8]) < 0) is(w + ": none", got == null);
            else arr(w, new int[] { i(r[8]), i(r[9]) }, got);
            str(w + ": rule", (String) r[10], String.valueOf(why[0]));
            if (before != null) is(w + ": Leafia's layout is the same object", got == before);
        }

        // ---------------------------------------------------------------- the log lines
        str("aa line, far only", "aa ev 7 side 1 angle -1 -> far 162 (stock) / near none",
                Turns.aaLine(7, 1, -1, 162, "stock", 162, 330f, "near-onramp"));
        str("aa line, near on-ramp", "aa ev 7 side 1 angle -1 -> far 162 (stock) / near 13 @315 (near-onramp)",
                Turns.aaLine(7, 1, -1, 162, "stock", 13, 315f, "near-onramp"));
        str("aa line, near fork", "aa ev 9 side 2 angle 0 -> far 173 (leafia) / near 13 @22.5 (near-fork)",
                Turns.aaLine(9, 2, 0, 173, "leafia", 13, 22.5f, "near-fork"));
        str("aa line, Leafia's turn", "aa ev 4 side 2 angle 0 -> far 67 (leafia) / near 13 @90 (leafia)",
                Turns.aaLine(4, 2, 0, 67, "leafia", 13, 90f, "leafia"));
        str("cp line, far only", "cp type 9 side 0 junction 0 exit none state 1 -> far 160 (stock) / near none",
                Turns.cpLine(new int[] { 9, 0, 0, 0, 0, 1, 800 }, 160, "stock", 160, 0f, "near-onramp"));
        str("cp line, near", "cp type 13 side 0 junction 0 exit -20 state 1 -> far 71 (gap) / near 13 @340 (leafia)",
                Turns.cpLine(new int[] { 13, 0, 0, -20, 1, 1, 120 }, 71, "gap", 13, 340f, "leafia"));
        str("cp line, no icon", "cp type 0 side 0 junction 0 exit none state 1 -> far 8 (kp-fallback) / near none",
                Turns.cpLine(new int[] { 0, 0, 0, 0, 0, 1, -1 }, 8, "kp-fallback", 8, 0f, "none"));
        str("cp line, no facts", "cp type ? side ? junction ? exit ? state ? -> far 70 (none) / near none",
                Turns.cpLine(null, 70, "none", 70, 0f, "none"));

        if (bad == 0) System.out.println("turns: all " + ok + " passed");
        else System.out.println("turns: " + bad + " FAILED, " + ok + " passed");
        System.exit(bad == 0 ? 0 : 1);
    }
}
