/*
 * jmk-autoplay-hud: CodeSum (0.1.3). Copyright JMK. AGPL-3.0, as the rest of this package (LICENSE).
 *
 *   CLASSPATH=tools/codesum.jar app_process /system/bin jmkhud.CodeSum <app.odex>...
 *   CLASSPATH=tools/codesum.jar app_process /system/bin jmkhud.CodeSum extract <app.odex> <code.dex>   (0.1.4)
 *   CLASSPATH=tools/codesum.jar app_process /system/bin jmkhud.CodeSum apkdex <app.apk>                (0.1.23)
 *
 * Prints one line, "<App>.code=<md5>" per argument (space separated; "none" when the file is not a Dalvik odex): the
 * md5 of the dex inside the odex, i.e. the bytes its "dey" header points at (dexOffset at 8, dexLength at 12, both
 * little-endian). Cars whose apps run the same code have that same dex inside different .odex files (the odex header and
 * its dependency list carry their framework's checksums), so this is what tells whether a patch set made for one car's
 * code fits another car. It is the same value gen5w-Evergreen's `lpatch odexdex` reports and keys its universal patches
 * with. Only read: nothing is written.
 *
 * extract (0.1.4): writes that dex to <code.dex> and prints "code=<md5>", or "code=none" (and no file) when the odex is
 * not one; the by-code build (scripts/common.sh) rebuilds an app's modified code from it with lpatch delta.
 *
 * apkdex (0.1.23, GFQ4GE5F, Casper Korea, 2026-11-22): prints "dex=<md5>" of the classes.dex inside the apk (a by-code
 * build: the car's own stock apk with our result dex added), or "dex=none". The .apk around our dex differs from car to
 * car, so only the dex tells our by-code build apart from a foreign file.
 */
package jmkhud;

import java.io.File;
import java.io.RandomAccessFile;
import java.security.MessageDigest;

public final class CodeSum {
    private CodeSum() { }

    public static void main(String[] args) {
        if (args.length == 2 && "apkdex".equals(args[0])) {
            String s = apkDex(args[1]);
            System.out.println("dex=" + (s == null ? "none" : s));
            return;
        }
        if (args.length == 3 && "extract".equals(args[0])) {
            String s = copy(args[1], args[2]);
            System.out.println("code=" + (s == null ? "none" : s));
            return;
        }
        StringBuilder b = new StringBuilder();
        for (String p : args) {
            String n = new File(p).getName();
            if (n.endsWith(".odex")) n = n.substring(0, n.length() - 5);
            String s = sum(p);
            if (b.length() > 0) b.append(' ');
            b.append(n).append(".code=").append(s == null ? "none" : s);
        }
        System.out.println(b);
    }

    static String sum(String path) { return copy(path, null); }

    /** The md5 of the dex inside the odex at path, written to out when out is not null; null when it is no odex. */
    static String copy(String path, String out) {
        RandomAccessFile f = null;
        java.io.FileOutputStream o = null;
        File outFile = out == null ? null : new File(out);
        if (outFile != null) outFile.delete();   // never an older file left where the caller looks
        try {
            f = new RandomAccessFile(path, "r");
            byte[] h = new byte[40];
            f.readFully(h);
            if (h[0] != 'd' || h[1] != 'e' || h[2] != 'y' || h[3] != '\n' || h[4] != '0' || h[5] != '3' || h[7] != 0) return null;
            long off = u32(h, 8), len = u32(h, 12);
            if (off < 40 || len < 112 || off + len > f.length()) return null;
            f.seek(off);
            byte[] magic = new byte[4];
            f.readFully(magic);
            if (magic[0] != 'd' || magic[1] != 'e' || magic[2] != 'x' || magic[3] != '\n') return null;
            MessageDigest md = MessageDigest.getInstance("MD5");
            md.update(magic);
            if (outFile != null) { o = new java.io.FileOutputStream(outFile); o.write(magic); }
            byte[] buf = new byte[65536];
            long left = len - 4;
            while (left > 0) {
                int r = f.read(buf, 0, (int)Math.min(buf.length, left));
                if (r < 0) throw new java.io.EOFException(path);   // the catch removes the partial file
                md.update(buf, 0, r);
                if (o != null) o.write(buf, 0, r);
                left -= r;
            }
            if (o != null) { o.close(); o = null; }
            StringBuilder s = new StringBuilder();
            for (byte x : md.digest()) s.append(Character.forDigit((x >> 4) & 15, 16)).append(Character.forDigit(x & 15, 16));
            return s.toString();
        } catch (Exception e) {
            if (o != null) try { o.close(); } catch (Exception ignored) { }
            o = null;
            if (outFile != null) outFile.delete();
            return null;
        } finally {
            if (f != null) try { f.close(); } catch (Exception ignored) { }
            if (o != null) try { o.close(); } catch (Exception ignored) { }
        }
    }

    /** The md5 of the apk's classes.dex, or null (no such entry, not a zip). */
    static String apkDex(String path) {
        java.util.zip.ZipFile z = null;
        try {
            z = new java.util.zip.ZipFile(path);
            java.util.zip.ZipEntry e = z.getEntry("classes.dex");
            if (e == null) return null;
            java.io.InputStream in = z.getInputStream(e);
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] buf = new byte[65536];
            for (int r; (r = in.read(buf)) > 0; ) md.update(buf, 0, r);
            in.close();
            StringBuilder s = new StringBuilder();
            for (byte x : md.digest()) s.append(Character.forDigit((x >> 4) & 15, 16)).append(Character.forDigit(x & 15, 16));
            return s.toString();
        } catch (Exception ex) {
            return null;
        } finally {
            if (z != null) try { z.close(); } catch (Exception ignored) { }
        }
    }

    private static long u32(byte[] b, int o) {
        return (b[o] & 255L) | (b[o + 1] & 255L) << 8 | (b[o + 2] & 255L) << 16 | (b[o + 3] & 255L) << 24;
    }
}
