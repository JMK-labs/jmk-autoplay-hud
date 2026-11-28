package com.tcc.iap2;

import java.util.ArrayList;
import java.util.List;

/** Test double of the head unit's class (same names and accessors the DiPO code calls): a message built from items. */
public class Iap2NotiMsg {
    public Iap2ObjGroup group;

    public Iap2ObjGroup getItemGroup() { return group; }

    public static class Iap2ObjGroup {
        public final List<Iap2ObjItem> items = new ArrayList<Iap2ObjItem>();
        public int getItemCnt() { return items.size(); }
        public Iap2ObjItem getObjItem(int i) { return items.get(i); }
    }

    public static class Iap2ObjItem {
        public final int id, type;
        public int[] ints;
        public byte[] bytes;
        public Iap2ObjGroup[] groups;
        public String[] strings;
        public Iap2ObjItem(int id, int type) { this.id = id; this.type = type; }
        public int getItemId() { return id; }
        public int getItemParamType() { return type; }
        public int getItemObjCount() { return ints != null ? ints.length : bytes != null ? bytes.length : groups != null ? groups.length : 0; }
        public int[] getItemIntArray() { return ints; }
        public byte[] getItemByteArray() { return bytes; }
        public Iap2ObjGroup[] getItemGroupArray() { return groups; }
        public String[] getItemStringArray() { return strings; }
    }
}
