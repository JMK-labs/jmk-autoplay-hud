package com.jmk.hud;

import android.bluetooth.BluetoothDevice;
import android.os.ParcelUuid;

import java.util.Locale;

/**
 * jmk-autoplay-hud 0.1.22 (AGPL-3.0, as this package): which Bluetooth phone the CarPlay bridge treats as an iPhone
 * (com.ev6.cpwl.Bridge.isApple, called when a phone connects, and for its SPP status and data).
 *
 * <p>The bridge asks the firmware for the phone's Device ID vendor (BluetoothDevice.getVendor(), which this firmware
 * has) and takes Apple (0x4C) only. Before the phone's Device ID record has come in, getVendor() answers 0, and the
 * bridge then said "not an iPhone" without looking any further, so that connection got no wireless CarPlay channel.
 *
 * <p>Now: Apple's vendor id is an iPhone and another maker's is not, as before. An unknown vendor (0), or a build
 * without getVendor(), is looked at further: the iAP2 service an iPhone lists over Bluetooth (UUID
 * 00000000-deca-fade-deca-deafdecacaff), then the name (iPhone / iPad, the bridge's own fallback).
 */
public final class Apple {
    static final int APPLE_VENDOR_ID = 0x4c;
    static final String IAP2_UUID_PART = "deca-fade-deca-deaf";

    private Apple() {
    }

    public static boolean is(BluetoothDevice d) {
        if (d == null) {
            return false;
        }
        int vendor = -1;
        try {
            Object v = BluetoothDevice.class.getMethod("getVendor").invoke(d);
            if (v instanceof Integer) {
                vendor = ((Integer) v).intValue();
            }
        } catch (Throwable t) {
            // no getVendor() on this build: as unknown
        }
        if (vendor == APPLE_VENDOR_ID) {
            return true;
        }
        if (vendor > 0) {
            return false;
        }
        try {
            ParcelUuid[] uuids = d.getUuids();
            if (uuids != null) {
                for (ParcelUuid u : uuids) {
                    if (u != null && u.toString().toLowerCase(Locale.US).indexOf(IAP2_UUID_PART) >= 0) {
                        return true;
                    }
                }
            }
        } catch (Throwable t) {
            // no service list yet: the name
        }
        try {
            String n = d.getName();
            return n != null && (n.contains("iPhone") || n.contains("iPad"));
        } catch (Throwable t) {
            return false;
        }
    }
}
