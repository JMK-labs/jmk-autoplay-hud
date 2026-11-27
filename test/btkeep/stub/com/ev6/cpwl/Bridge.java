package com.ev6.cpwl;
public class Bridge { static volatile boolean sCpWireless; static volatile boolean sUsb; public static void set(boolean w, boolean u) { sCpWireless = w; sUsb = u; } }
