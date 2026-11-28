package com.hkmc.cluster;

/** Test double of the cluster service: records every lane frame it is given. */
public class NavigationCluster {
    public static final java.util.List<byte[]> FRAMES = new java.util.ArrayList<byte[]>();
    public NavigationCluster(android.content.Context c) { }
    public void updateLaneInfo(byte[] f) { FRAMES.add(f.clone()); }
    public void updateTBTSubInfo2C(int a, int b, int c, int d, int e, int f, int g, int h, int i) { }
    public void updateRemainDis(int a, int b, int c, int d) { }
    public void updateTBTInfo(int a, int b, float c, float d, int e, int f, int g, int h, int i) { }
}
