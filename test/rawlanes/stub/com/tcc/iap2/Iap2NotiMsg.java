package com.tcc.iap2;

import java.util.ArrayList;
import java.util.List;

/** Test double of the head unit's class: a message built from (id, type, bytes) items. */
public class Iap2NotiMsg {
    public Iap2ObjGroup group;
    public static boolean boom;

    public Iap2ObjGroup getItemGroup() { return group; }

    public static class Iap2ObjGroup {
        public final List<Iap2ObjItem> items = new ArrayList<Iap2ObjItem>();
        public int getItemCnt() { return items.size(); }
        public Iap2ObjItem getObjItem(int i) { if (boom) throw new IllegalStateException("boom"); return items.get(i); }
    }

    public static class Iap2ObjItem {
        public final int id, type;
        public final byte[] bytes;
        public Iap2ObjItem(int id, int type, byte[] bytes) { this.id = id; this.type = type; this.bytes = bytes; }
        public int getItemId() { return id; }
        public int getItemParamType() { return type; }
        public byte[] getItemByteArray() { return bytes; }
    }
}
