/*
 * jmk-autoplay-hud: CodeSum (0.1.3). Copyright JMK. AGPL-3.0, as the rest of this package (LICENSE).
 *
 *   CLASSPATH=tools/codesum.jar app_process /system/bin jmkhud.CodeSum <app.odex>...
 *
 * Prints one line, "<App>.code=<md5>" per argument (space separated; "none" when the file is not a Dalvik odex): the
 * md5 of the dex inside the odex, i.e. the bytes its "dey" header points at (dexOffset at 8, dexLength at 12, both
 * little-endian). Cars whose apps run the same code have that same dex inside different .odex files (the odex header and
 * its dependency list carry their framework's checksums), so this is what tells whether a patch set made for one car's
 * code fits another car. It is the same value gen5w-Evergreen's `lpatch odexdex` reports and keys its universal patches
 * with. Only read: nothing is written.
 */
package jmkhud;

import java.io.File;
import java.io.RandomAccessFile;
import java.security.MessageDigest;

public final class CodeSum {
    private CodeSum() { }

    public static void main(String[] args) {
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

    static String sum(String path) {
        RandomAccessFile f = null;
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
            byte[] buf = new byte[65536];
            long left = len - 4;
            while (left > 0) {
                int r = f.read(buf, 0, (int)Math.min(buf.length, left));
                if (r < 0) return null;
                md.update(buf, 0, r);
                left -= r;
            }
            StringBuilder s = new StringBuilder();
            for (byte x : md.digest()) s.append(Character.forDigit((x >> 4) & 15, 16)).append(Character.forDigit(x & 15, 16));
            return s.toString();
        } catch (Exception e) {
            return null;
        } finally {
            if (f != null) try { f.close(); } catch (Exception ignored) { }
        }
    }

    private static long u32(byte[] b, int o) {
        return (b[o] & 255L) | (b[o + 1] & 255L) << 8 | (b[o + 2] & 255L) << 16 | (b[o + 3] & 255L) << 24;
    }
}
