import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

public final class HttpHost {
    private static final int GUEST_TIMEOUT_SECONDS = 10;

    private HttpHost() { }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("usage: HttpHost <stitched-WebServer.ores>");
        }

        Map<String, Route> routes = loadRoutes(Path.of(args[0]));
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));

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
        String compiler = System.getenv().getOrDefault("ORESLANG_COMPILER", "oreslang-compiler");
        Process process = new ProcessBuilder(
                compiler,
                "--platform=server",
                source.toString()
        ).start();

        if (!process.waitFor(GUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            process.destroyForcibly();
            throw new IllegalStateException("Oreslang guest exceeded the demo timeout");
        }

        String stdout = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        String stderr = new String(process.getErrorStream().readAllBytes(), StandardCharsets.UTF_8);
        if (process.exitValue() != 0) {
            throw new IllegalStateException("Oreslang guest failed: " + stderr);
        }

        List<String> lines = stdout.lines().toList();
        if (lines.isEmpty() || lines.size() % 3 != 0) {
            throw new IllegalStateException("invalid route manifest from Oreslang");
        }

        Map<String, Route> routes = new LinkedHashMap<>();
        for (int i = 0; i < lines.size(); i += 3) {
            String path = lines.get(i);
            if (!path.startsWith("/") || routes.containsKey(path)) {
                throw new IllegalStateException("invalid or duplicate route: " + path);
            }
            routes.put(path, new Route(lines.get(i + 1), lines.get(i + 2)));
        }
        return Map.copyOf(routes);
    }

    private static void handle(HttpExchange exchange, Map<String, Route> routes) throws IOException {
        if (!"GET".equalsIgnoreCase(exchange.getRequestMethod())) {
            send(exchange, 405, "text/plain; charset=utf-8", "method not allowed\n");
            return;
        }

        Route route = routes.get(exchange.getRequestURI().getPath());
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
        exchange.sendResponseHeaders(status, bytes.length);
        try (var output = exchange.getResponseBody()) {
            output.write(bytes);
        }
    }

    private record Route(String contentType, String body) { }
}
