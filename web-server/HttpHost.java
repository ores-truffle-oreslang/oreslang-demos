import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

public final class HttpHost {
    private static final int GUEST_TIMEOUT_SECONDS = 10;
    private static final int MAX_GUEST_OUTPUT_BYTES = 1024 * 1024;
    private static final int MAX_ROUTES = 256;
    private static final int MAX_TRACKED_DESCENDANTS = 256;
    private static final long DESCENDANT_SCAN_NANOS = TimeUnit.MILLISECONDS.toNanos(25);
    private static final int MAX_PATH_CHARS = 2048;
    private static final int MAX_CONTENT_TYPE_CHARS = 256;

    private HttpHost() { }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("usage: HttpHost <stitched-WebServer.ores>");
        }

        Path source = Path.of(args[0]).toAbsolutePath().normalize();
        if (!Files.isRegularFile(source)) {
            throw new IllegalArgumentException("not a regular Oreslang source file: " + source);
        }

        int port = parsePort(System.getenv().getOrDefault("PORT", "8080"));
        Map<String, Route> routes = loadRoutes(source);

        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
        server.createContext("/", exchange -> handle(exchange, routes));
        server.setExecutor(Executors.newFixedThreadPool(4));
        server.start();

        System.out.println("Oreslang web demo listening on http://127.0.0.1:" + port);
        for (String path : routes.keySet()) {
            System.out.println("  " + path);
        }
    }

    private static Map<String, Route> loadRoutes(Path source) throws Exception {
        GuestOutput guest = runGuest(source);
        if (guest.exitCode() != 0) {
            throw new IllegalStateException(
                    "Oreslang guest failed with exit code " + guest.exitCode() + ": " + guest.stderr());
        }

        List<String> lines = guest.stdout().lines().toList();
        if (lines.isEmpty() || lines.size() % 3 != 0 || lines.size() / 3 > MAX_ROUTES) {
            throw new IllegalStateException("invalid route manifest from Oreslang");
        }

        Map<String, Route> routes = new LinkedHashMap<>();
        for (int i = 0; i < lines.size(); i += 3) {
            String path = lines.get(i);
            String contentType = lines.get(i + 1);
            String body = lines.get(i + 2);

            validatePath(path);
            validateContentType(contentType);
            if (routes.putIfAbsent(path, new Route(contentType, body)) != null) {
                throw new IllegalStateException("duplicate route: " + path);
            }
        }
        return Map.copyOf(routes);
    }

    private static GuestOutput runGuest(Path source) throws Exception {
        String compiler = System.getenv().getOrDefault("ORESLANG_COMPILER", "oreslang-compiler");
        Process process = new ProcessBuilder(
                compiler,
                "--platform=server",
                source.toString()
        ).start();

        // The deadline covers process exit AND both pipe captures. Closing an
        // ExecutorService waits for blocked readers, even after the compiler
        // exits if a child inherits stdout/stderr. Never close/join it here.
        long deadlineNanos = System.nanoTime()
                + TimeUnit.SECONDS.toNanos(GUEST_TIMEOUT_SECONDS);
        var io = Executors.newVirtualThreadPerTaskExecutor();
        Future<String> stdout = null;
        Future<String> stderr = null;
        Map<Long, ProcessHandle> observedDescendants = new LinkedHashMap<>();
        try {
            stdout = io.submit(
                    () -> readUtf8Bounded(process.getInputStream(), MAX_GUEST_OUTPUT_BYTES));
            stderr = io.submit(
                    () -> readUtf8Bounded(process.getErrorStream(), MAX_GUEST_OUTPUT_BYTES));

            // Observe descendants before their direct parent exits; reparented
            // children otherwise disappear from ProcessHandle.descendants().
            while (true) {
                observeDescendants(process, observedDescendants);
                long remaining = deadlineNanos - System.nanoTime();
                if (remaining <= 0) {
                    throw new IllegalStateException("Oreslang guest exceeded the demo timeout");
                }
                if (process.waitFor(Math.min(remaining, DESCENDANT_SCAN_NANOS),
                        TimeUnit.NANOSECONDS)) {
                    break;
                }
            }

            return new GuestOutput(
                    process.exitValue(),
                    getCaptured(stdout, "stdout", deadlineNanos),
                    getCaptured(stderr, "stderr", deadlineNanos)
            );
        } finally {
            if (stdout != null) stdout.cancel(true);
            if (stderr != null) stderr.cancel(true);
            io.shutdownNow();
            // Best-effort cleanup, not an OS sandbox. A process group or job
            // object is needed to catch forks between descendant scans.
            for (ProcessHandle child : observedDescendants.values()) {
                if (child.isAlive()) child.destroyForcibly();
            }
            if (process.isAlive()) process.destroyForcibly();
        }
    }

    private static void observeDescendants(Process process,
                                           Map<Long, ProcessHandle> observed) {
        try (var children = process.toHandle().descendants()) {
            children.forEach(child -> {
                observed.putIfAbsent(child.pid(), child);
                if (observed.size() > MAX_TRACKED_DESCENDANTS) {
                    throw new IllegalStateException("guest descendant process budget exceeded");
                }
            });
        }
    }

    private static String readUtf8Bounded(InputStream input, int maxBytes) throws IOException {
        ByteArrayOutputStream kept = new ByteArrayOutputStream(Math.min(maxBytes, 8192));
        byte[] buffer = new byte[8192];
        long total = 0;
        int read;

        while ((read = input.read(buffer)) != -1) {
            long before = total;
            total += read;
            if (before < maxBytes) {
                int keep = (int) Math.min(read, maxBytes - before);
                kept.write(buffer, 0, keep);
            }
        }

        if (total > maxBytes) {
            throw new IOException("guest output exceeded " + maxBytes + " bytes");
        }
        return kept.toString(StandardCharsets.UTF_8);
    }

    private static String getCaptured(Future<String> future, String streamName,
                                      long deadlineNanos) throws Exception {
        long remaining = deadlineNanos - System.nanoTime();
        if (remaining <= 0) {
            throw new IllegalStateException("guest " + streamName + " capture exceeded deadline");
        }
        try {
            return future.get(remaining, TimeUnit.NANOSECONDS);
        } catch (java.util.concurrent.TimeoutException error) {
            throw new IllegalStateException(
                    "guest " + streamName + " capture exceeded deadline", error);
        } catch (ExecutionException error) {
            throw new IOException("failed to capture guest " + streamName, error.getCause());
        }
    }

    private static int parsePort(String raw) {
        final int port;
        try {
            port = Integer.parseInt(raw);
        } catch (NumberFormatException error) {
            throw new IllegalArgumentException("PORT must be an integer", error);
        }
        if (port < 1 || port > 65535) {
            throw new IllegalArgumentException("PORT must be between 1 and 65535");
        }
        return port;
    }

    private static void validatePath(String path) {
        if (!canonicalRequestTarget(path, null)) {
            throw new IllegalStateException("invalid route path: " + path);
        }
    }

    static boolean canonicalRequestTarget(String rawPath, String rawQuery) {
        if (rawQuery != null || rawPath == null || rawPath.isEmpty()
                || rawPath.charAt(0) != '/'
                || rawPath.length() > MAX_PATH_CHARS
                || rawPath.indexOf('%') >= 0
                || rawPath.indexOf('\\') >= 0
                || rawPath.indexOf('\r') >= 0
                || rawPath.indexOf('\n') >= 0
                || rawPath.indexOf('\0') >= 0
                || rawPath.indexOf('?') >= 0
                || rawPath.indexOf('#') >= 0
                || rawPath.contains("//")
                || rawPath.chars().anyMatch(ch -> ch < 0x21 || ch > 0x7e)) {
            return false;
        }
        for (String segment : rawPath.split("/", -1)) {
            if (".".equals(segment) || "..".equals(segment)) {
                return false;
            }
        }
        return true;
    }

    private static void validateContentType(String contentType) {
        if (contentType.isBlank()
                || contentType.length() > MAX_CONTENT_TYPE_CHARS
                || contentType.indexOf('\r') >= 0
                || contentType.indexOf('\n') >= 0
                || contentType.indexOf('\0') >= 0) {
            throw new IllegalStateException("invalid content type");
        }
    }

    private static void handle(HttpExchange exchange, Map<String, Route> routes) throws IOException {
        String rawPath = exchange.getRequestURI().getRawPath();
        String rawQuery = exchange.getRequestURI().getRawQuery();
        if (!canonicalRequestTarget(rawPath, rawQuery)) {
            send(exchange, 400, "text/plain; charset=utf-8", "noncanonical request target\n");
            return;
        }

        if (!"GET".equalsIgnoreCase(exchange.getRequestMethod())) {
            exchange.getResponseHeaders().set("Allow", "GET");
            send(exchange, 405, "text/plain; charset=utf-8", "method not allowed\n");
            return;
        }

        Route route = routes.get(rawPath);
        if (route == null) {
            send(exchange, 404, "text/plain; charset=utf-8", "not found\n");
            return;
        }

        send(exchange, 200, route.contentType(), route.body());
    }

    private static void send(HttpExchange exchange, int status, String contentType, String body)
            throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", contentType);
        exchange.getResponseHeaders().set("Cache-Control", "no-store");
        exchange.getResponseHeaders().set("X-Content-Type-Options", "nosniff");
        exchange.sendResponseHeaders(status, bytes.length);
        try (var output = exchange.getResponseBody()) {
            output.write(bytes);
        } finally {
            exchange.close();
        }
    }

    private record Route(String contentType, String body) { }
    private record GuestOutput(int exitCode, String stdout, String stderr) { }
}
