package com.jmk.hud;

/**
 * jmk-autoplay-hud 0.1.34 (AGPL-3.0, as this package): which turn picture the cluster and the HUD get for a maneuver
 * of the phone, where the stock Korean navigation's numbers differ from the ones the patched HKMC_GPM (Android Auto)
 * and HKMC_DiPO (CarPlay) builds carried so far. No Android in it (the hooks' side is TurnsOut; test/turns runs this
 * class on the JVM, every row of the tables below).
 *
 * Two pictures exist: the far icon (the small turn icon of the turn frame, also the HUD list's) and the near layout
 * (display 13 turn point with a direction, 17 / 18 expressway exit right / left, ... sent inside the window D).
 *
 * Android Auto (event, side: 1 left, 2 right):
 *   far   ON_RAMP  right / left / none   173 / 174 / 172 -> 161 / 162 / 160   (expressway entry, the stock numbers)
 *         OFF_RAMP right / left / none    81 /  82 /  86 -> 164 / 165 / 163   (expressway exit; 81 / 82 are the stock
 *                                                                              overpass / ground divergence pictures)
 *   near  ON_RAMP  right / left / none   none -> 13 at 45 / 315 / 0 degrees   (a ramp reads as a 45 degree arrow)
 *         FORK     right / left          25 (Y) -> 13 at 22.5 / 337.5 degrees, side-street bits 3 / 16386 (the way
 *                                        out and the other road: right fork bits 1 and 0, left fork bits 14 and 1)
 * CarPlay (iAP2 maneuver type, driving side, junction type, exit angle):
 *   far   the stock table's own numbers where the build had others: on-ramp 9 172 -> 160, expressway exit left / right
 *         22 / 23 82 / 81 -> 165 / 164, left-hand traffic roundabout rows 96..107 -> 192..203;
 *         where the stock table has no row: an exit with an angle (near 17 / 18) 81 / 82 -> 164 / 165, exit 8 or
 *         change expressway 51 without one -> 163, keep left / right 13 / 14 174 / 173 -> 71 / 66, a left / right /
 *         sharp / slight turn (1, 2, 47-50) at an angle the table does not list -> slight up to 67 degrees, turn up
 *         to 112, sharp past that (a type that says sharp or slight keeps that), anything else the build left without
 *         a number -> a number by type or angle, 8 (no icon) at the least: the previous arrow never stays.
 *   near  on-ramp 9: none -> 13 at the exit angle (0 without one); change expressway 51 / 52 / 53: none -> 17 / 18.
 *
 * Ported from an AGPL-3.0 Korean-firmware mod code base (turn pictures, 2.4.8 generation),
 * AGPL-3.0: the Android Auto ramp type, the near display and other-road bit, which rows the stock
 * table has, the banded turn, the fallback icon, the roundabout icon, the near display.
 * Ported, adapted: the
 * method, not its code; it sits on Leafia's turn code (it only changes what is listed above), directions are degrees
 * as Leafia's frames carry them, the window D is Near's (0.1.33). The stock numbers themselves are the car's own
 * (stock HKMC_DiPO table; the Korean stock GPM manager of other models for Android Auto's ramps).
 *
 * Nothing here ever throws.
 */
public final class Turns {
    private Turns() {
    }

    // ------------------------------------------------------------------------------------------------ Android Auto
    /** Android Auto's maneuver events and sides (NavigationNextTurnEvent) */
    static final int AA_ON_RAMP = 7, AA_OFF_RAMP = 8, AA_FORK = 9, LEFT = 1, RIGHT = 2;
    /** the near layout "turn point with a direction", expressway exit right / left, and "no icon" */
    static final int NEAR_TURN = 13, NEAR_EXIT_RIGHT = 17, NEAR_EXIT_LEFT = 18, NO_ICON = 8;

    /** the far icon of a ramp: the number the build's manager chose (US numbers) -> the Korean stock number */
    public static int aaFar(int event, int side, int icon) {
        if (event == AA_ON_RAMP) {
            if (icon == 173) return 161;
            if (icon == 174) return 162;
            if (icon == 172) return 160;
        } else if (event == AA_OFF_RAMP) {
            if (icon == 81) return 164;
            if (icon == 82) return 165;
            if (icon == 86) return 163;
        }
        return icon;
    }

    /** which rule gave Android Auto's far icon (for the log) */
    static String aaFarRule(int event, int far) {
        if (event == AA_ON_RAMP && far >= 160 && far <= 162) return "stock";
        if (event == AA_OFF_RAMP && far >= 163 && far <= 165) return "stock";
        return "leafia";
    }

    /** the bar of a distance inside the window d: 10 x floor(m x 10 / d), 10..90 (as LeafiaStandard.bar) */
    static int bar(int meters, int d) {
        if (d <= 0) return 0;
        int b = (int) ((long) meters * 10L / d);
        if (b < 1) b = 1;
        if (b > 9) b = 9;
        return b * 10;
    }

    /**
     * Android Auto's near layout for an on-ramp or a fork inside the window (meters 0..d): {display, direction in
     * whole degrees, bar, side-street bits, direction in tenths of a degree}; null for everything else (Leafia's own
     * layout, or none). The fifth value is what the turn frame's direction gets (TurnsOut.aaDir): a fork is 22.5 /
     * 337.5 degrees.
     */
    public static int[] aaNear(int event, int side, int meters, int d) {
        if (meters < 0 || meters > d) return null;
        if (event == AA_ON_RAMP) {
            int deg = side == RIGHT ? 45 : side == LEFT ? 315 : 0;
            return new int[] { NEAR_TURN, deg, bar(meters, d), 0, deg * 10 };
        }
        if (event == AA_FORK) {
            if (side == RIGHT) return new int[] { NEAR_TURN, 22, bar(meters, d), (1 << 1) | 1, 225 };
            if (side == LEFT) return new int[] { NEAR_TURN, 337, bar(meters, d), (1 << 14) | (1 << 1), 3375 };
        }
        return null;
    }

    /** which rule gave Android Auto's near layout (for the log); ours tells whether aaNear gave it */
    static String aaNearRule(int event, boolean ours) {
        if (!ours) return "leafia";
        return event == AA_ON_RAMP ? "near-onramp" : "near-fork";
    }

    /** the direction of the turn frame: the fifth value of aaNear's result when there is one, else as it was */
    public static float aaDir(int[] result, float dir) {
        if (result != null && result.length >= 5) return result[4] / 10f;
        return dir;
    }

    // ------------------------------------------------------------------------------------------------ CarPlay
    /** an angle as -179..180 (right is +) */
    static int signed(int a) {
        int n = ((a % 360) + 360) % 360;
        return n > 180 ? n - 360 : n;
    }

    /**
     * The stock table's own number for a row the build changed: on-ramp 9 (172 -> 160), expressway exit left / right
     * 22 / 23 (82 / 81 -> 165 / 164), and the roundabout rows of left-hand traffic (driving side 1, junction 1:
     * 96..107 -> 192..203, the stock B family).
     */
    static int cpStock(int type, int side, int junction, int icon) {
        if (type == 9 && icon == 172) return 160;
        if (type == 22 && icon == 82) return 165;
        if (type == 23 && icon == 81) return 164;
        if (side == 1 && junction == 1) {
            switch (icon) {
                case 96: case 97: case 99: case 100: case 102: case 104: case 105: case 107: return icon + 96;
                default: break;
            }
        }
        return icon;
    }

    /**
     * A plain turn at an angle the stock table does not list: slight up to 67 degrees, turn up to 112, sharp past
     * that; a type that says sharp (47, 48) or slight (49, 50) keeps that. 0: not such a turn (no angle, a
     * roundabout, another type).
     */
    static int banded(int type, int junction, int exit) {
        if (junction != 0 || exit == 0) return 0;
        boolean left;
        switch (type) {
            case 1: case 47: case 49: left = true; break;
            case 2: case 48: case 50: left = false; break;
            default: return 0;
        }
        int a = Math.abs(exit);
        if (a > 180) a = 360 - a;
        int sharp = type == 47 || type == 48 ? 2 : type == 49 || type == 50 ? 0 : a <= 67 ? 0 : a <= 112 ? 1 : 2;
        return left ? 71 - sharp : 66 + sharp;
    }

    /** a roundabout exit by its angle: the stock table's exits first, then the nearest of the 8 directions (A family) */
    static int roundabout(int side, int exit) {
        int e = signed(exit);
        if (side == 1) {
            switch (e) {
                case 0: return 97;
                case 90: return 99;
                case 120: return 100;
                case 180: return 102;
                case -120: return 104;
                case -90: return 105;
                case -30: return 107;
                default: break;
            }
        } else {
            switch (e) {
                case 0: return 96;
                case 90: return 99;
                case 135: return 100;
                case 180: return 102;
                case -45: return 104;
                case -90: return 105;
                case -135: return 104;
                default: break;
            }
        }
        int a = Math.abs(e);
        if (a <= 22) return 96;
        if (a >= 158) return 102;
        if (e > 0) return a <= 67 ? 97 : a <= 112 ? 99 : 100;
        return a <= 67 ? 107 : a <= 112 ? 105 : 104;
    }

    /**
     * A number for a maneuver neither the stock table nor Leafia's projection has one for: the stock number of the
     * type whatever the angle, else by the angle, else by the type alone, else NO_ICON (never "straight" for a turn).
     */
    static int fallback(int type, int side, int junction, int exit) {
        switch (type) {
            case 11: return NO_ICON;              // start of the route: no turn
            case 8: case 51: return 163;          // exit ramp, change expressway: expressway exit, straight
            case 9: return 160;                   // on-ramp
            case 22: return 165;                  // expressway exit left
            case 23: return 164;                  // expressway exit right
            case 16: case 17: return 176;         // ferry
            case 20: return 70;                   // left at the end of the road
            case 21: return 67;                   // right at the end of the road
            case 26: return side == 1 ? 73 : 72;  // U-turn when possible
            case 27: return 112;                  // end of directions
            default: break;
        }
        int b = banded(type, junction, exit);
        if (b != 0) return b;
        if (exit != 0) {
            if (junction != 0) return roundabout(side, exit);
            boolean left;
            switch (type) {
                case 1: case 47: case 49: case 13: left = true; break;
                case 2: case 48: case 50: case 14: left = false; break;
                default: left = exit < 0; break;
            }
            int deg = Math.abs(exit);
            if (deg > 180) deg = 360 - deg;
            if (deg >= 157) return side == 0 ? 72 : 73;
            if (deg <= 22 && type != 1 && type != 2) return 65;
            int sharp = deg <= 67 ? 0 : deg <= 112 ? 1 : 2;
            return left ? 71 - sharp : 66 + sharp;
        }
        switch (type) {
            case 1: return 70;
            case 2: return 67;
            case 47: return 69;
            case 48: return 68;
            case 49: return 71;
            case 50: return 66;
            case 13: return 71;
            case 14: return 66;
            case 3: return 65;
            case 4: case 18: return side == 0 ? 72 : 73;
            case 5: return 172;
            case 6: return side == 0 ? 96 : 97;
            case 10: case 12: return 112;
            case 15: return 176;
            default: return NO_ICON;
        }
    }

    /**
     * CarPlay's far icon. type, side, junction, exit, known (the phone gave an exit angle), state: the maneuver's
     * facts (LeafiaCpStandard.facts); table: the number of the build's table (with Leafia's simple-maneuver rows; 0:
     * no row); leafia: the number after Leafia's projection (the table's when it has one). why[0] gets the rule:
     *   "stock"        the stock table's own number for a row the build changed
     *   "table"        the table's number as it is
     *   "band"         a turn at an angle the table does not list
     *   "gap"          a stock number for a maneuver the table has no row for (exit with an angle, keep left / right)
     *   "leafia"       Leafia's projection as it is
     *   "kp-fallback"  a number where the build had none
     */
    public static int cpFar(int type, int side, int junction, int exit, boolean known, int state, int table, int leafia,
                            String[] why) {
        if (table != 0) {
            int s = cpStock(type, side, junction, table);
            why[0] = s != table ? "stock" : "table";
            return s;
        }
        if (leafia == 3) {   // arrived
            why[0] = "leafia";
            return leafia;
        }
        int e = known ? signed(exit) : 0;
        int b = banded(type, junction, e);
        if (b != 0) {
            why[0] = "band";
            return b;
        }
        if (leafia != 0) {
            int g = leafia == 81 ? 164 : leafia == 82 ? 165 : leafia == 174 && type == 13 ? 71
                    : leafia == 173 && type == 14 ? 66 : leafia;
            why[0] = g != leafia ? "gap" : "leafia";
            return g;
        }
        why[0] = "kp-fallback";
        return fallback(type, side, junction, e);
    }

    /**
     * CarPlay's near layout {display, direction in degrees}. leafia: what LeafiaCpStandard.nativeTurn gave (null:
     * none); it stays when there is one. Without one: on-ramp 9 at an intersection is a turn point at the exit angle
     * (0 without one), change expressway 52 / 53 is the exit left / right, 51 the exit by its angle (left when
     * negative, or without an angle in left-hand traffic). why[0] gets "leafia", "near-onramp", "near-highway" or
     * "none".
     */
    public static int[] cpNear(int[] leafia, int type, int side, int junction, int exit, boolean known, int state,
                               String[] why) {
        if (leafia != null) {
            why[0] = "leafia";
            return leafia;
        }
        why[0] = "none";
        if (state == 2) return null;
        int e = known ? signed(exit) : 0;
        if (type == 9) {
            if (junction != 0) return null;
            why[0] = "near-onramp";
            return new int[] { NEAR_TURN, e != 0 && Math.abs(e) < 180 ? (e + 360) % 360 : 0 };
        }
        if (type == 51 || type == 52 || type == 53) {
            boolean left = type == 52 || (type == 51 && (e < 0 || (e == 0 && side == 1)));
            why[0] = "near-highway";
            return left ? new int[] { NEAR_EXIT_LEFT, 270 } : new int[] { NEAR_EXIT_RIGHT, 90 };
        }
        return null;
    }

    // ------------------------------------------------------------------------------------------------ the log lines
    /** "ev E side S angle A -> far F (rule) / near D @DIR (rule)" (near none: the far picture is what is shown) */
    static String aaLine(int event, int side, int angle, int far, String farRule, int display, float dir, String nearRule) {
        return "aa ev " + event + " side " + side + " angle " + angle + " -> far " + far + " (" + farRule + ") / "
                + near(far, display, dir, nearRule);
    }

    /** "type T side S junction J exit E state St -> far F (rule) / near D @DIR (rule)" (exit none: no angle given) */
    static String cpLine(int[] facts, int far, String farRule, int display, float dir, String nearRule) {
        String in = facts == null || facts.length < 6 ? "type ? side ? junction ? exit ? state ?"
                : "type " + facts[0] + " side " + facts[1] + " junction " + facts[2] + " exit "
                + (facts[4] != 0 ? String.valueOf(facts[3]) : "none") + " state " + facts[5];
        return "cp " + in + " -> far " + far + " (" + farRule + ") / " + near(far, display, dir, nearRule);
    }

    private static String near(int far, int display, float dir, String rule) {
        if (display == far || display >= 64) return "near none";
        String d = dir == (int) dir ? String.valueOf((int) dir) : String.valueOf(dir);
        return "near " + display + " @" + d + " (" + rule + ")";
    }
}
