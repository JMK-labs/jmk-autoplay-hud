package com.hkmc.cluster;

/**
 * Compile-only stub (jmk-autoplay-hud 0.1.19): the calls TbtClear makes on the head unit's own
 * com.hkmc.cluster.NavigationCluster (boot class path, /system/framework). Never built into a dex: src/tbt/build.sh and
 * src/tbt/clear.sh compile it on the class path only, and only com/jmk/hud goes into the dex.
 */
public class NavigationCluster {
    public static class DestinationName {
        public int type;
        public String name;
    }

    public NavigationCluster(android.content.Context context) {
        throw new RuntimeException("stub");
    }

    public void updateTBTInfo(int displayType, int sideStreet, float direction, float distance, int distanceErr,
                              int combiSideStreet, int scale, int barGraphLevel, int barGraphLevelErr) {
        throw new RuntimeException("stub");
    }

    public void updateTBTSubInfo(float a, int b, int c, int d, int e, int f, int g, float h, int i, int j) {
        throw new RuntimeException("stub");
    }

    public void updateTBTSubInfo2C(int a, int b, int c, int d, int e, int f, int g, int h, int i) {
        throw new RuntimeException("stub");
    }

    public void updateLaneInfo(byte[] lanes) {
        throw new RuntimeException("stub");
    }

    public void updateTPTurnListNew(byte[] list) {
        throw new RuntimeException("stub");
    }

    public void updateTPFlexibleDestinationName(DestinationName name) {
        throw new RuntimeException("stub");
    }
}
