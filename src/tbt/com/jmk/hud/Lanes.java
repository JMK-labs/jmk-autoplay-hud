// jmk-autoplay-hud 0.1.29 (AGPL-3.0, as this package). Ported, adapted from HMG-Seogaemo (AGPL-3.0),
// https://github.com/seogaemo/hmg-seogaemo, commit fbaacf7 (v0.1.58), modules/wireless-carplay-and-aa/payload/src/hmgapi/mods/wireless/dipo/:
//   CpLaneFrame.java (lane), CpTurns.java (laneValues, LaneGlyphs table and find, laneIcon).
//
package com.jmk.hud;

import java.util.Arrays;

/**
 * The cluster's lane values for a CarPlay lane, as the phone shows it: every arrow of a multi-direction lane from the
 * matching component glyphs; white for a good lane, blue for the lane that must be used, grey for a lane that is not
 * good; an arrow on the route lit and the lane's other arrows grey.
 *
 * <p>Use in the DiPO bridge build (src/tbt/lanes.sh): {@link #begin()} at the start of the stock-side lane builder
 * (u.applyLanes), {@link #record(int, int[], int[])} from u.laneOne with the raw LaneStatus, LaneAngles and
 * LaneAngleHighlight of each lane, and {@link #patch(byte[])} on the finished 81-byte 0xF1 frame before it is gated and
 * sent: for every lane it can compute it overwrites the status byte (3+k) and the three arrow bytes (19+3k..21+3k); any
 * other byte, and any lane it cannot compute, stays as Leafia's code built it. Nothing here throws out; on any problem the
 * frame is left as it was. The DiPO message handler is one thread; the entry points are synchronized all the same.
 *
 * <p>One lane as {status byte, arrow image id of slot 0, 1, 2}: the status byte holds 2 bits per arrow slot, slot 0
 * lowest: 00 not drawn, 01 white, 10 blue, 11 grey.
 */
public final class Lanes {
    public static final int WHITE = 1, BLUE = 2, GREY = 3;

    /** Leafia's lane log: public static void capture(tag, caller, mode, before, after, note). */
    static final String LOG_TAG = "cp", LOG_CALLER = "Lanes.patch";

    // ------------------------------------------------------------------------------------------------ the frame hook

    private static final int MAX = 8;
    private static int count;
    private static final int[] sStatus = new int[MAX];
    private static final int[][] sAngles = new int[MAX][];
    private static final int[][] sHighlight = new int[MAX][];

    private Lanes() {
    }

    /** a new lane frame starts: forget the lanes of the last one */
    public static synchronized void begin() {
        try {
            count = 0;
            for (int k = 0; k < MAX; k++) {
                sAngles[k] = null;
                sHighlight[k] = null;
            }
        } catch (Throwable t) {
            count = 0;
        }
    }

    /** one lane's raw values (status -1 when the phone sent none; the arrays null when it sent none); at most 8 lanes */
    public static synchronized void record(int status, int[] angles, int[] highlight) {
        try {
            if (count >= MAX) {
                count = MAX + 1;   // more lanes than a frame holds: patch() will leave the frame alone
                return;
            }
            sStatus[count] = status;
            sAngles[count] = angles == null ? null : angles.clone();
            sHighlight[count] = highlight == null ? null : highlight.clone();
            count++;
        } catch (Throwable t) {
            count = MAX + 1;
        }
    }

    /**
     * the finished frame of the lanes recorded since {@link #begin()}: the lane values of the reference rule go into the
     * frame in place. The frame's lane count (byte 1) must equal the number of lanes recorded, else nothing is changed.
     */
    public static synchronized void patch(byte[] frame) {
        byte[] before = null;
        try {
            if (frame == null || frame.length < 81 || (frame[0] & 0xff) != 0xf1) {
                return;
            }
            int n = frame[1] & 0xff;
            if (n != count || n > MAX) {
                return;
            }
            before = frame.clone();
            int[][] values = new int[n][];
            for (int k = 0; k < n; k++) {
                values[k] = laneValues(sStatus[k], sAngles[k], sHighlight[k]);
            }
            for (int k = 0; k < n; k++) {
                int[] v = values[k];
                if (v == null) {
                    continue;
                }
                frame[3 + k] = (byte) v[0];
                for (int j = 0; j < 3; j++) {
                    frame[19 + 3 * k + j] = (byte) v[1 + j];
                }
            }
            log(before, frame, n, values);
        } catch (Throwable t) {
            if (before != null) {
                System.arraycopy(before, 0, frame, 0, before.length);
            }
        } finally {
            count = 0;
        }
    }

    /** one line in Leafia's lane log (persist.leafia.lane.log): the lane count, then per lane the status byte and the glyph ids */
    private static void log(byte[] before, byte[] after, int n, int[][] values) {
        try {
            StringBuilder sb = new StringBuilder(" lanes n=").append(n).append(" [");
            for (int k = 0; k < n; k++) {
                if (k > 0) {
                    sb.append(' ');
                }
                int[] v = values[k];
                if (v == null) {
                    sb.append("keep");
                } else {
                    sb.append(String.format("%02x:%d/%d/%d", v[0], v[1], v[2], v[3]));
                }
            }
            sb.append(']');
            com.leafia.kr.LeafiaLane.capture(LOG_TAG, LOG_CALLER, 0, before, after, sb.toString());
        } catch (Throwable t) {
            // the log is never worth a lane frame
        }
    }

    // ------------------------------------------------------------------------------------------------ the lane rule

    /**
     * One lane from the phone's values: status (0 not good, 1 good, 2 preferred, anything else counts as good), the angles
     * (degrees, 0 straight, negative left, positive right; one outside -180..180 is skipped) and the highlight angles (an
     * arrow is on the route when its angle equals one; none valid, or none matching, means all match).
     *
     * @return {status byte, image id of slot 0, 1, 2}, or null when it cannot be computed
     */
    public static int[] laneValues(int status, int[] angles, int[] highlights) {
        try {
            int[] cls = new int[8];
            int n = 0, onRoute = 0;
            if (angles != null) {
                for (int k = 0; k < angles.length; k++) {
                    int a = angles[k];
                    if (a < -180 || a > 180) {
                        continue;
                    }
                    int c = laneIcon(a), i = 0;
                    while (i < n && cls[i] != c) {
                        i++;
                    }
                    if (i == n) {
                        cls[n++] = c;
                    }
                    if (highlights != null) {
                        for (int h : highlights) {
                            if (h == a) {
                                onRoute |= 1 << i;
                            }
                        }
                    }
                }
            }
            return lane(Arrays.copyOf(cls, n), onRoute, status);
        } catch (Throwable t) {
            return null;
        }
    }

    /**
     * @param arrows  the lane's arrow slots as direction classes 1..8 (0: unused), at most 8
     * @param onRoute bit k set: the direction in slot k is on the route (the phone's highlight)
     * @param status  CarPlay's LaneStatus: 0 not good, 1 good, 2 preferred (anything else counts as 1)
     * @return {status byte, image id of slot 0, 1, 2}, or null for a null array
     *
     * <p>Status 1 (good): the arrows on the route white, the other arrows of that lane grey; no arrow on the route:
     * every arrow white. Status 2 (preferred, the lane the driver must use): the same, with blue instead of white. Status
     * 0 (not good): every arrow grey.
     */
    public static int[] lane(int[] arrows, int onRoute, int status) {
        try {
            if (arrows == null) {
                return null;
            }
            int on = status == 2 ? BLUE : WHITE;
            int[] cls = new int[8];
            boolean[] rec = new boolean[8];
            int n = 0;
            for (int k = 0; k < arrows.length && k < 8; k++) {
                int c = arrows[k];
                if (c < 1 || c > 8) {
                    continue;
                }
                int i = 0;
                while (i < n && cls[i] != c) {
                    i++;
                }
                if (i == n) {
                    cls[n++] = c;
                }
                if ((onRoute >> k & 1) != 0) {
                    rec[i] = true;
                }
            }
            int[] r = new int[4];
            int idle = status == 0 ? GREY : on;
            if (n == 0) {
                r[0] = idle;
                return r;
            }
            boolean anyRec = false;
            for (int i = 0; i < n; i++) {
                anyRec |= rec[i];
            }
            boolean snap = false;
            int[][] row = find(cls, n, false);
            if (row == null) {
                row = find(cls, n, true);
                snap = row != null;
            }
            if (row == null) {
                // not a verified set: only the route arrow, else the first, as a single plain glyph
                int pick = 0;
                for (int i = n - 1; i >= 0; i--) {
                    if (rec[i]) {
                        pick = i;
                    }
                }
                row = new int[][] { { cls[pick] }, { cls[pick] } };
                rec = new boolean[] { rec[pick], false, false };
                cls = new int[] { cls[pick], 0, 0 };
                n = 1;
            }
            for (int j = 0; j < row[0].length; j++) {
                boolean slotRec = false;
                for (int i = 0; i < n; i++) {
                    if (rec[i] && fold(cls[i], snap) == row[0][j]) {
                        slotRec = true;
                    }
                }
                int colour = status == 0 ? GREY : !anyRec || slotRec ? on : GREY;
                r[0] |= colour << (2 * j);
                r[1 + j] = row[1][j];
            }
            return r;
        } catch (Throwable t) {
            return null;
        }
    }

    /** a lane angle (degrees, right positive) as the cluster's arrow: 1 straight, 2-4 right, 5 back, 6-8 left */
    static int laneIcon(int a) {
        if (a > 180) {
            a -= 360;
        } else if (a < -180) {
            a += 360;
        }
        if (a >= 0) {
            if (a <= 22) {
                return 1;
            }
            if (a <= 67) {
                return 2;
            }
            if (a <= 112) {
                return 3;
            }
            return a <= 157 ? 4 : 5;
        }
        a = -a;
        if (a <= 22) {
            return 1;
        }
        if (a <= 67) {
            return 8;
        }
        if (a <= 112) {
            return 7;
        }
        return a <= 157 ? 6 : 5;
    }

    // ------------------------------------------------------------------------------------------------ the glyph table

    /**
     * Image ids for the arrows of a multi-direction lane, car-verified 2026-11-05. Single directions use the plain ids
     * 1..8 (laneIcon values, which double as the direction classes here). Each row is {direction classes in slot order,
     * image ids in slot order}; the lane's set of directions matches a row whatever order the phone lists its angles in.
     */
    static final int ST = 1, SLR = 2, R = 3, SHR = 4, UT = 5, SHL = 6, L = 7, SLL = 8;
    static final int[][][] SETS = {
        { { UT, L }, { 10, 14 } },
        { { UT, SLL }, { 10, 15 } },
        { { ST, L }, { 9, 12 } },
        { { ST, SLL }, { 9, 13 } },
        { { ST, SHL }, { 9, 11 } },
        { { ST, UT }, { 9, 10 } },
        { { L, SLL }, { 12, 13 } },
        { { ST, R }, { 16, 18 } },
        { { ST, SLR }, { 16, 19 } },
        { { ST, SHR }, { 16, 17 } },
        { { R, SLR }, { 18, 21 } },
        { { L, R }, { 31, 32 } },
        { { SLL, SLR }, { 30, 33 } },
        { { UT, R }, { 26, 32 } },
        { { UT, SLR }, { 26, 33 } },
        { { L, ST, R }, { 28, 22, 24 } },
        { { SLL, ST, R }, { 30, 22, 24 } },
        { { L, ST, SLR }, { 28, 22, 33 } },
        { { SHL, ST, R }, { 27, 22, 24 } },
        { { L, ST, SHR }, { 28, 22, 25 } },
        { { SLL, ST, SLR }, { 30, 22, 33 } },
        { { L, SLL, ST }, { 12, 13, 9 } },
        { { ST, SLR, R }, { 16, 19, 18 } },
        { { UT, L, ST }, { 26, 31, 22 } },
        { { UT, ST, R }, { 26, 22, 24 } },
        { { UT, L, R }, { 26, 31, 32 } },
    };

    /** snap: slight and sharp turns count as the plain left / right */
    static int fold(int c, boolean snap) {
        if (!snap) {
            return c;
        }
        return c == SLR || c == SHR ? R : c == SLL || c == SHL ? L : c;
    }

    /** the row for the classes cls[0..n) (one class: the plain glyph), or null when none matches */
    static int[][] find(int[] cls, int n, boolean snap) {
        int mask = 0, kinds = 0, first = 0;
        for (int i = 0; i < n; i++) {
            int c = fold(cls[i], snap);
            if ((mask & (1 << c)) != 0) {
                continue;
            }
            mask |= 1 << c;
            if (kinds++ == 0) {
                first = c;
            }
        }
        if (kinds == 1) {
            return new int[][] { { first }, { first } };
        }
        for (int[][] row : SETS) {
            int m = 0;
            for (int c : row[0]) {
                m |= 1 << c;
            }
            if (m == mask) {
                return row;
            }
        }
        return null;
    }
}
