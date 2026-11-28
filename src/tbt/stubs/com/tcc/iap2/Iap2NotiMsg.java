package com.tcc.iap2;

/** Compile-only stand-in for the head unit's own classes of the same names (never in the dex; only the calls RawLanes makes). */
public class Iap2NotiMsg {
    public Iap2ObjGroup getItemGroup() { return null; }

    public static class Iap2ObjGroup {
        public int getItemCnt() { return 0; }
        public Iap2ObjItem getObjItem(int i) { return null; }
    }

    public static class Iap2ObjItem {
        public int getItemId() { return 0; }
        public int getItemParamType() { return 0; }
        public byte[] getItemByteArray() { return null; }
    }
}
