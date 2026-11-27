package jmkhud.link.android;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.SocketTimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;

import android.net.Credentials;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;

import jmkhud.link.ReadTimeout;
import jmkhud.link.Transport;
import jmkhud.link.Wire;

/**
 * The one Android transport: Transport over android.net.LocalSocket in the abstract namespace (API 1). Every client,
 * in our daemons and in the hooks, uses this class; nothing else in our code writes a line to such a socket. Android 4.4 rules it
 * follows (android-4.4.2_r1 source, checked on a car 2026-11-26):
 * <ul>
 * <li>never LocalSocket.connect(addr, timeout): unsupported on Android. A plain connect returns at once when nobody listens and blocks
 *     only while the listener's backlog is full; callers with a budget connect on a helper thread.</li>
 * <li>never flush(): the output stream has no buffer (write() goes to the kernel at once), and its flush() sleeps until the kernel's
 *     send queue is empty, i.e. until the PEER has read everything, with no deadline.</li>
 * <li>writes are bounded by SO_TIMEOUT: 4.4's setSoTimeout sets SO_RCVTIMEO and SO_SNDTIMEO; set at the start (WRITE_MS) and by each
 *     readLine. A line of at most Wire.MAX_LINE fits the socket buffer, so a write blocks only when the peer stopped reading.</li>
 * <li>a read timeout comes as a plain IOException: mapped by {@link ReadTimeout}.</li>
 * </ul>
 */
public final class LocalSockets {
    private LocalSockets() { }

    /** The bound on a write before any read set its own timeout, ms. */
    public static final int WRITE_MS = 3000;

    /** A connector to an abstract name. */
    public static Transport.Connector connector(final String name) {
        return new Transport.Connector() {
            public Transport.Conn open() throws IOException {
                LocalSocket s = new LocalSocket();
                try {
                    s.connect(new LocalSocketAddress(name, LocalSocketAddress.Namespace.ABSTRACT));
                    return new Conn(s);
                } catch (IOException e) {
                    try { s.close(); } catch (Throwable t) { /* closed */ }
                    throw e;
                }
            }
        };
    }

    /** One connection. {@link #closed()} runs once after the socket is closed (the server side closes an accepted fd there). */
    public static class Conn implements Transport.Conn {
        private final LocalSocket s;
        private final InputStream in;
        private final OutputStream out;
        private final int uid, pid;
        private final AtomicBoolean done = new AtomicBoolean();
        private final byte[] buf = new byte[Wire.MAX_LINE + 1];
        private int have;

        public Conn(LocalSocket s) throws IOException {
            this.s = s;
            this.in = s.getInputStream();
            this.out = s.getOutputStream();
            int u = -1, p = -1;
            try {
                Credentials c = s.getPeerCredentials();
                if (c != null) { u = c.getUid(); p = c.getPid(); }
            } catch (IOException e) { /* unknown: -1 */ }
            this.uid = u;
            this.pid = p;
            try { s.setSoTimeout(WRITE_MS); } catch (IOException e) { /* the first readLine sets it */ }
        }

        /** The socket, for a subclass. */
        protected final LocalSocket socket() { return s; }

        /** One line, no flush (see the class comment). */
        public synchronized void writeLine(String line) throws IOException {
            out.write((line + "\n").getBytes("UTF-8"));
        }

        public String readLine(int timeoutMs) throws IOException {
            s.setSoTimeout(timeoutMs);
            while (true) {
                for (int i = 0; i < have; i++) {
                    if (buf[i] == '\n') {
                        String line = new String(buf, 0, i, "UTF-8");
                        System.arraycopy(buf, i + 1, buf, 0, have - i - 1);
                        have -= i + 1;
                        return line;
                    }
                }
                if (have >= Wire.MAX_LINE) throw new IOException("line too long");
                int n;
                long t0 = System.currentTimeMillis();
                try {
                    n = in.read(buf, have, buf.length - have);
                } catch (SocketTimeoutException e) {
                    throw e;
                } catch (IOException e) {
                    throw ReadTimeout.map(e, System.currentTimeMillis() - t0, timeoutMs);
                }
                if (n < 0) return null;
                have += n;
            }
        }

        public int peerUid() { return uid; }

        public int peerPid() { return pid; }

        /** Once: shut both ways (wakes a blocked reader or writer), close, then {@link #closed()}. */
        public final void close() {
            if (!done.compareAndSet(false, true)) return;
            try { s.shutdownInput(); } catch (Throwable t) { /* closed */ }
            try { s.shutdownOutput(); } catch (Throwable t) { /* closed */ }
            try { s.close(); } catch (Throwable t) { /* closed */ }
            closed();
        }

        /** After the socket is closed, once. Nothing for a client. */
        protected void closed() { }
    }
}
