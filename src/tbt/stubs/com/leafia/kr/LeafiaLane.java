package com.leafia.kr;

/**
 * Compile-only stub (jmk-autoplay-hud 0.1.29): the one call Lanes makes on Leafia's own com.leafia.kr.LeafiaLane (the lane
 * log of the DiPO build; public static, same signature as in the build). Never built into a dex: src/tbt/lanes.sh compiles
 * it on the class path only, and only com/jmk/hud goes into the dex.
 */
public final class LeafiaLane {
    private LeafiaLane() {
    }

    public static void capture(String tag, String caller, int mode, byte[] before, byte[] after, String note) {
        throw new RuntimeException("stub");
    }
}
