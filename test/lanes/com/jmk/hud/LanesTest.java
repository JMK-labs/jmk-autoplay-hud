package com.jmk.hud;

import java.util.Arrays;

/**
 * jmk-autoplay-hud 0.1.29: src/tbt/com/jmk/hud/Lanes.java on the Mac JVM (test/check-scripts.sh runs it). The lane cases are
 * HMG-Seogaemo's (github.com/seogaemo/hmg-seogaemo, commit fbaacf7, CpTurnsTest lane section) with their expected values,
 * plus the car-verified status bytes of the lane arrows, five cases of JMK's own
 * and the frame hook (begin / record / patch) with a recording double of Leafia's lane log.
 */
public final class LanesTest {
    static int ok, bad;

    static void check(String what, boolean good) {
        if (good) {
            ok++;
        } else {
            bad++;
            System.out.println("FAIL  " + what);
        }
    }

    static int[] i(int... v) {
        return v;
    }

    static void laneIs(String what, int[] r, int status, int... ids) {
        boolean good = r != null && r[0] == status;
        for (int k = 0; k < 3 && r != null; k++) {
            good &= r[1 + k] == (k < ids.length ? ids[k] : 0);
        }
        check(what + (r == null ? " (null)" : " (status " + Integer.toHexString(r[0]) + ", ids " + r[1] + "," + r[2] + "," + r[3] + ")"), good);
    }

    static byte[] frame(int n) {
        byte[] f = new byte[81];
        f[0] = (byte) 0xf1;
        f[1] = (byte) n;
        for (int k = 0; k < n; k++) {
            f[3 + k] = (byte) 0x7e;                  // Leafia's bytes: recognisable
            for (int j = 0; j < 3; j++) {
                f[19 + 3 * k + j] = (byte) (0x60 + k * 3 + j);
            }
        }
        f[2] = 0x5a;                                 // pockets and trailer must survive
        f[0x43] = 0x11;
        f[0x50] = 0x22;
        return f;
    }

    public static void main(String[] a) {
        // ------------------------------------------------------------------ angle -> arrow (CpTurnsTest)
        check("lane angles: 0 straight, 90 right, -45 slight left, 180 back, 270 wraps to left",
                Lanes.laneIcon(0) == 1 && Lanes.laneIcon(90) == 3 && Lanes.laneIcon(-45) == 8 && Lanes.laneIcon(180) == 5
                        && Lanes.laneIcon(270) == 7);

        // ------------------------------------------------------------------ glyph pairs and per-arrow status (CpTurnsTest)
        laneIs("U-turn + left, good lane, route left: U-turn grey, left white", Lanes.laneValues(1, i(180, -90), i(-90)), 0x07, 10, 14);
        laneIs("U-turn + left listed left first: same slots", Lanes.laneValues(1, i(-90, 180), i(-90)), 0x07, 10, 14);
        laneIs("U-turn + left, preferred lane, route left: left blue", Lanes.laneValues(2, i(180, -90), i(-90)), 0x0b, 10, 14);
        laneIs("U-turn + left, not-good lane: both grey", Lanes.laneValues(0, i(180, -90), i(-90)), 0x0f, 10, 14);
        laneIs("U-turn + left, good lane, route U-turn", Lanes.laneValues(1, i(180, -90), i(180)), 0x0d, 10, 14);
        laneIs("U-turn + left, preferred lane, route U-turn", Lanes.laneValues(2, i(180, -90), i(180)), 0x0e, 10, 14);
        laneIs("straight + left, good lane, route straight: 9 + 12, white + grey", Lanes.laneValues(1, i(0, -90), i(0)), 0x0d, 9, 12);
        laneIs("straight + left, good lane, route left: grey + white", Lanes.laneValues(1, i(0, -90), i(-90)), 0x07, 9, 12);
        laneIs("left + straight + right, preferred, route right: 28 22 24, blue on the right only", Lanes.laneValues(2, i(-90, 0, 90), i(90)), 0x2f, 28, 22, 24);
        laneIs("left + straight + right listed in another order, good, route straight", Lanes.laneValues(1, i(90, -90, 0), i(0)), 0x37, 28, 22, 24);
        laneIs("sharp left + straight + slight right is not listed: snapped to left + straight + right", Lanes.laneValues(2, i(-135, 0, 45), i(45)), 0x2f, 28, 22, 24);
        laneIs("slight left + slight right is listed as is: 30 + 33", Lanes.laneValues(1, i(-45, 45), i(-45)), 0x0d, 30, 33);
        laneIs("sharp + slight left snap to one left glyph", Lanes.laneValues(1, i(-135, -45), i(-45)), 0x01, 7);
        laneIs("... preferred: blue", Lanes.laneValues(2, i(-135, -45), i(-45)), 0x02, 7);
        laneIs("four directions, preferred: only the highlighted arrow, right (3), blue", Lanes.laneValues(2, i(-90, 0, 90, 180), i(90)), 0x02, 3);
        laneIs("four directions, good lane with no highlight: the first arrow, white", Lanes.laneValues(1, i(-90, 0, 90, 180), i(1000)), 0x01, 7);
        laneIs("four directions, preferred with no highlight: the first arrow, blue", Lanes.laneValues(2, i(-90, 0, 90, 180), i(1000)), 0x02, 7);
        laneIs("four directions, not-good lane: the first arrow, grey", Lanes.laneValues(0, i(-90, 0, 90, 180), i(1000)), 0x03, 7);
        laneIs("preferred without a highlight: every arrow blue", Lanes.laneValues(2, i(0, -90), i(1000)), 0x0a, 9, 12);
        laneIs("good lane without a highlight: every arrow white", Lanes.laneValues(1, i(0, -90), i(1000)), 0x05, 9, 12);
        laneIs("a highlight that matches no arrow counts as none", Lanes.laneValues(1, i(0, -90), i(45)), 0x05, 9, 12);
        laneIs("single direction keeps the plain glyph; two angles of one direction are one arrow", Lanes.laneValues(2, i(85, 95), i(95)), 0x02, 3);
        laneIs("a not-good single arrow is grey", Lanes.laneValues(0, i(90), i(1000)), 0x03, 3);
        laneIs("angle outside -180..180 is skipped", Lanes.laneValues(1, i(1000, 90), i(1000)), 0x01, 3);
        laneIs("a status that is not 0..2 counts as good", Lanes.laneValues(-1, i(90), i(1000)), 0x01, 3);
        check("no usable angle: the lane's value on slot 0 only (preferred blue, good white, not good grey)",
                Lanes.laneValues(2, null, i(1000))[0] == 2 && Lanes.laneValues(1, null, i(1000))[0] == 1
                        && Lanes.laneValues(0, null, i(1000))[0] == 3 && Lanes.laneValues(2, null, i(1000))[1] == 0);
        laneIs("right + slight right as the 18 + 21 pair, route right white, slight right grey (status 0d)", Lanes.laneValues(1, i(90, 45), i(90)), 0x0d, 18, 21);

        // Android Auto's equivalent lanes (CpTurnsTest): lane() and laneValues() agree, and never blue for status 1 / 0
        int[] angleOf = { 0, 0, 45, 90, 135, 180, -135, -90, -45 };
        boolean same = true, noBlue = true;
        for (int c1 = 1; c1 <= 8; c1++) {
            for (int c2 = 0; c2 <= 8; c2++) {
                for (int mask = 0; mask < 4; mask++) {
                    if (c1 == c2) {
                        continue;
                    }
                    int[] arrows = c2 == 0 ? new int[] { c1 } : new int[] { c1, c2 };
                    if (mask >= 1 << arrows.length) {
                        continue;
                    }
                    int[] angles = arrows.length == 1 ? i(angleOf[c1]) : i(angleOf[c1], angleOf[c2]);
                    for (int other = 0; other < 2; other++) {
                        int st = mask != 0 || other == 0 ? 1 : 0;
                        int[] aa = Lanes.lane(arrows, mask, st);
                        int[] high = mask == 0 ? i(1000) : mask == 3 ? i(angleOf[c1], angleOf[c2]) : mask == 1 ? i(angleOf[c1]) : i(angleOf[c2]);
                        int[] cpv = Lanes.laneValues(st, angles, high);
                        same &= Arrays.equals(aa, cpv);
                        for (int j = 0; j < 3; j++) {
                            noBlue &= (aa[0] >> 2 * j & 3) != 2;
                        }
                    }
                }
            }
        }
        check("lane() equals laneValues() for every one- and two-arrow lane (status 1 highlighted, status 0 other lanes)", same);
        check("status 1 and 0 lanes are never blue", noBlue);

        // ------------------------------------------------------------------ car-verified status bytes (cluster-lane-arrows.md)
        laneIs("0x01: one normal arrow", Lanes.lane(i(1), 0, 1), 0x01, 1);
        laneIs("0x05: two normal arrows (straight + left, no arrow on the route)", Lanes.lane(i(1, 7), 0, 1), 0x05, 9, 12);
        laneIs("0x15: three normal arrows (left + straight + right)", Lanes.lane(i(7, 1, 3), 0, 1), 0x15, 28, 22, 24);
        laneIs("0x0d: a white straight + a grey left", Lanes.lane(i(1, 7), 1, 1), 0x0d, 9, 12);
        laneIs("0x07: a grey straight + a white left", Lanes.lane(i(1, 7), 2, 1), 0x07, 9, 12);
        laneIs("0x0b: the second arrow blue after a grey first (preferred lane, route second)", Lanes.lane(i(1, 7), 2, 2), 0x0b, 9, 12);
        check("0x09 (white first + blue second) is a frame the cluster draws but the rule never makes: no lane gives it", noNine());
        laneIs("U-turn + left lane: both slots drawn, glyphs 10 + 14, normal 0x05", Lanes.lane(i(5, 7), 0, 1), 0x05, 10, 14);
        laneIs("U-turn + left lane, listed left first, same slots", Lanes.lane(i(7, 5), 0, 1), 0x05, 10, 14);

        // ------------------------------------------------------------------ the five cases of cp-lanes-PHASE0.md
        laneIs("phase 0 case 1: one straight lane, status 1", Lanes.laneValues(1, i(0), null), 0x01, 1);
        laneIs("phase 0 case 2: straight + left, highlight left, status 1", Lanes.laneValues(1, i(0, -90), i(-90)), 0x07, 9, 12);
        laneIs("phase 0 case 3: U-turn + left, status 2", Lanes.laneValues(2, i(180, -90), null), 0x0a, 10, 14);
        laneIs("phase 0 case 4: three arrows, status 0", Lanes.laneValues(0, i(0, -90, 90), null), 0x3f, 28, 22, 24);
        laneIs("phase 0 case 5: highlight 1000, status 1 (one straight lane)", Lanes.laneValues(1, i(0), i(1000)), 0x01, 1);
        laneIs("phase 0 case 5b: highlight 1000 does not light a U-turn (status 1)", Lanes.laneValues(1, i(180, -90), i(1000)), 0x05, 10, 14);
        laneIs("phase 0 case 1b: a highlight on the only arrow of a good lane is white, not blue", Lanes.laneValues(1, i(0), i(0)), 0x01, 1);
        laneIs("phase 0 x8: two angles of one class are one arrow", Lanes.laneValues(1, i(0, 10), null), 0x01, 1);

        // ------------------------------------------------------------------ bad input: null, never a throw
        check("lane: null arrows -> null", Lanes.lane(null, 0, 1) == null);
        laneIs("lane: out-of-range classes are skipped", Lanes.lane(i(0, 9, -1, 3), 0, 1), 0x01, 3);
        laneIs("lane: more than eight slots, only the first eight are looked at", Lanes.lane(i(0, 0, 0, 0, 0, 0, 0, 0, 3), 0, 1), 0x01);
        check("laneValues: no angles, no highlight -> a value, not null", Lanes.laneValues(1, null, null) != null);
        check("laneValues: an empty angle array -> a value", Lanes.laneValues(0, new int[0], new int[0])[0] == 3);

        // ------------------------------------------------------------------ the frame hook
        resetLog();
        Lanes.begin();
        Lanes.record(1, i(0, -90), i(-90));          // straight + left, route left, good
        Lanes.record(2, i(180, -90), null);          // U-turn + left, preferred
        byte[] f = frame(2);
        byte[] orig = f.clone();
        Lanes.patch(f);
        check("hook: lane 0 status byte", (f[3] & 0xff) == 0x07);
        check("hook: lane 0 arrows 9 12 0", f[19] == 9 && f[20] == 12 && f[21] == 0);
        check("hook: lane 1 status byte", (f[4] & 0xff) == 0x0a);
        check("hook: lane 1 arrows 10 14 0", f[22] == 10 && f[23] == 14 && f[24] == 0);
        boolean rest = true;
        for (int k = 0; k < 81; k++) {
            boolean lane = k == 3 || k == 4 || (k >= 19 && k <= 24);
            rest &= lane || f[k] == orig[k];
        }
        check("hook: count, pockets, every other lane slot and the trailer stay as Leafia built them", rest && f[2] == 0x5a && f[0x43] == 0x11 && f[0x50] == 0x22 && f[1] == 2);
        check("hook: one log line through Leafia's lane log (tag cp, caller Lanes.patch)", com.leafia.kr.LeafiaLane.calls == 1
                && "cp".equals(com.leafia.kr.LeafiaLane.tag) && "Lanes.patch".equals(com.leafia.kr.LeafiaLane.caller));
        check("hook: the log line has the lane count, status byte and glyph ids per lane", " lanes n=2 [07:9/12/0 0a:10/14/0]".equals(com.leafia.kr.LeafiaLane.note));
        check("hook: the log holds the frame before (Leafia's) and after", Arrays.equals(com.leafia.kr.LeafiaLane.before, orig) && Arrays.equals(com.leafia.kr.LeafiaLane.after, f));

        // the next frame starts clean; no leftovers of the last one
        Lanes.begin();
        Lanes.record(0, i(90), null);
        byte[] g = frame(1);
        Lanes.patch(g);
        check("hook: a second frame after begin: one grey right arrow", (g[3] & 0xff) == 0x03 && g[19] == 3 && g[20] == 0 && g[21] == 0);
        byte[] g2 = frame(1);
        byte[] g2o = g2.clone();
        Lanes.patch(g2);
        check("hook: patch twice without record: the second call changes nothing (the record is used once)", Arrays.equals(g2, g2o));

        // a mismatch between the lanes recorded and the frame's count: nothing changes
        Lanes.begin();
        Lanes.record(1, i(0), null);
        byte[] h = frame(2);
        byte[] ho = h.clone();
        Lanes.patch(h);
        check("hook: lane count 2 in the frame but 1 recorded: the frame is left as Leafia's", Arrays.equals(h, ho));
        Lanes.begin();
        Lanes.record(1, i(0), null);
        Lanes.record(1, i(0), null);
        byte[] h1 = frame(1);
        byte[] h1o = h1.clone();
        Lanes.patch(h1);
        check("hook: 1 in the frame but 2 recorded: left as Leafia's", Arrays.equals(h1, h1o));

        // more lanes than a frame holds
        Lanes.begin();
        for (int k = 0; k < 9; k++) {
            Lanes.record(1, i(0), null);
        }
        byte[] big = frame(8);
        byte[] bigo = big.clone();
        Lanes.patch(big);
        check("hook: nine lanes recorded: nothing changes", Arrays.equals(big, bigo));
        Lanes.begin();
        for (int k = 0; k < 8; k++) {
            Lanes.record(1, i(0), null);
        }
        byte[] eight = frame(8);
        Lanes.patch(eight);
        boolean e8 = true;
        for (int k = 0; k < 8; k++) {
            e8 &= (eight[3 + k] & 0xff) == 1 && eight[19 + 3 * k] == 1 && eight[20 + 3 * k] == 0 && eight[21 + 3 * k] == 0;
        }
        check("hook: eight lanes all patched", e8);

        // bad frames
        Lanes.begin();
        Lanes.record(1, i(0), null);
        Lanes.patch(null);
        byte[] shortF = new byte[40];
        shortF[0] = (byte) 0xf1;
        shortF[1] = 1;
        byte[] shortO = shortF.clone();
        Lanes.begin();
        Lanes.record(1, i(0), null);
        Lanes.patch(shortF);
        check("hook: null and short frames are left alone", Arrays.equals(shortF, shortO));
        byte[] notF1 = frame(1);
        notF1[0] = 0x10;
        byte[] notO = notF1.clone();
        Lanes.begin();
        Lanes.record(1, i(0), null);
        Lanes.patch(notF1);
        check("hook: a frame that is not a 0xF1 lane frame is left alone", Arrays.equals(notF1, notO));

        // the raw arrays are copied at record time
        int[] ang = i(0, -90);
        Lanes.begin();
        Lanes.record(1, ang, i(-90));
        ang[0] = 90;
        byte[] cp = frame(1);
        Lanes.patch(cp);
        check("hook: the arrays are copied when recorded (a later change in the caller's array does not matter)", (cp[3] & 0xff) == 0x07 && cp[19] == 9);

        // a lane the rule cannot make keeps Leafia's bytes (laneValues null is not reachable from valid input; a null status
        // array still gives a value), and a failing log never touches the frame
        resetLog();
        com.leafia.kr.LeafiaLane.fail = true;
        Lanes.begin();
        Lanes.record(1, i(0, -90), i(0));
        byte[] lf = frame(1);
        Lanes.patch(lf);
        com.leafia.kr.LeafiaLane.fail = false;
        check("hook: a failing log does not undo the lane values", (lf[3] & 0xff) == 0x0d && lf[19] == 9 && lf[20] == 12);

        // lane without any angle (Leafia could not draw this: the whole frame fell back to its raw bytes)
        Lanes.begin();
        Lanes.record(1, null, null);
        Lanes.record(2, i(0), i(0));
        byte[] na = frame(2);
        Lanes.patch(na);
        check("hook: a lane without angles gets its value on slot 0 only, the other lane its own", (na[3] & 0xff) == 0x01 && na[19] == 0 && na[20] == 0
                && (na[4] & 0xff) == 0x02 && na[22] == 1);

        System.out.println(bad == 0 ? "lanes: all " + ok + " passed" : "lanes: " + bad + " FAILED, " + ok + " passed");
        System.exit(bad == 0 ? 0 : 1);
    }

    static boolean noNine() {
        for (int c1 = 1; c1 <= 8; c1++) {
            for (int c2 = 1; c2 <= 8; c2++) {
                for (int mask = 0; mask < 4; mask++) {
                    for (int st = 0; st <= 2; st++) {
                        if (c1 != c2) {
                            int[] r = Lanes.lane(new int[] { c1, c2 }, mask, st);
                            if (r != null && (r[0] & 15) == 9) {
                                return false;
                            }
                        }
                    }
                }
            }
        }
        return true;
    }

    static void resetLog() {
        com.leafia.kr.LeafiaLane.calls = 0;
        com.leafia.kr.LeafiaLane.note = null;
    }
}
