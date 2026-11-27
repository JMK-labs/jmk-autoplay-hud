package jmkhud.link;

import java.io.IOException;

/**
 * JMK's own (AGPL-3.0 compatible). What the client needs from a local socket. On the car it is android.net.LocalSocket
 * (the android package), on the Mac a loopback stand-in of the tests.
 */
public interface Transport {
    /** One open connection. */
    interface Conn {
        /** Writes the line and a newline. Thread-safe: replies and subscribed events share one connection. */
        void writeLine(String line) throws IOException;

        /** One line without its newline; null at end of stream; java.net.SocketTimeoutException after {@code timeoutMs}. A line longer than Wire.MAX_LINE is an IOException. */
        String readLine(int timeoutMs) throws IOException;

        /** The uid of the other end (SO_PEERCRED), -1 when it cannot be read. */
        int peerUid();

        /** The pid of the other end, -1 when unknown. */
        int peerPid();

        /** Shuts both directions down, then closes. Never throws. */
        void close();
    }

    /** Opens a connection to the service; IOException when nobody listens (refused at once). Never connect with a timeout. */
    interface Connector {
        Conn open() throws IOException;
    }
}
