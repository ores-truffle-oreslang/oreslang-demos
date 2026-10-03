import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

public final class WebServer {
    private static final int GUEST_TIMEOUT_SECONDS = 10;

    private WebServer() { }

    public static void main(String[] args) throws Exception {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);

        server.createContext("/health", guestHandler("health.ores", "application/json; charset=utf-8"));
        server.createContext("/", exchange -> {
            if (!"/".equals(exchange.getRequestURI().getPath())) {
                send(exchange, 404, "text/plain; charset=utf-8", "not found\n".getBytes(StandardCharsets.UTF_8));
                return;
            }
            guestHandler("index.ores", "text/html; charset=utf-8").handle(exchange);
        });

        server.setExecutor(Executors.newFixedThreadPool(4));
        server.start();

        System.out.println("Oreslang web demo listening on http://127.0.0.1:" + port);
        System.out.println("Health endpoint: http://127.0.0.1:" + port + "/health");
    }

    private static HttpHandler guestHandler(String sourceFile, String contentType) {
        return exchange -> {
            if (!"GET".equalsIgnoreCase(exchange.getRequestMethod())) {
                send(exchange, 405, "text/plain; charset=utf-8",
                        "method not allowed\n".getBytes(StandardCharsets.UTF_8));
                return;
            }

            try {
                GuestResult result = runGuest(sourceFile);
                if (result.exitCode != 0) {
                    System.err.println("Oreslang guest failed: " + result.stderr);
                    send(exchange, 500, "text/plain; charset=utf-8",
                            "Oreslang guest failed\n".getBytes(StandardCharsets.UTF_8));
                    return;
                }
                send(exchange, 200, contentType, result.stdout);
            } catch (Exception error) {
                error.printStackTrace(System.err);
                send(exchange, 500, "text/plain; charset=utf-8",
                        "Oreslang guest failed\n".getBytes(StandardCharsets.UTF_8));
            }
        };
    }

    private static GuestResult runGuest(String sourceFile) throws Exception {
        String compiler = System.getenv().getOrDefault("ORESLANG_COMPILER", "oreslang-compiler");
        Process process = new ProcessBuilder(List.of(
                compiler,
                "--platform=server",
                sourceFile
        )).start();

        if (!process.waitFor(GUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            process.destroyForcibly();
            return new GuestResult(
                    124,
                    new byte[0],
                    "guest exceeded " + GUEST_TIMEOUT_SECONDS + " second timeout"
            );
        }

        byte[] stdout = process.getInputStream().readAllBytes();
        String stderr = new String(process.getErrorStream().readAllBytes(), StandardCharsets.UTF_8);
        return new GuestResult(process.exitValue(), stdout, stderr);
    }

    private static void send(HttpExchange exchange, int status, String contentType, byte[] body)
            throws IOException {
        exchange.getResponseHeaders().set("Content-Type", contentType);
        exchange.getResponseHeaders().set("Cache-Control", "no-store");
        exchange.sendResponseHeaders(status, body.length);
        try (var output = exchange.getResponseBody()) {
            output.write(body);
        }
    }

    private static final class GuestResult {
        private final int exitCode;
        private final byte[] stdout;
        private final String stderr;

        private GuestResult(int exitCode, byte[] stdout, String stderr) {
            this.exitCode = exitCode;
            this.stdout = stdout;
            this.stderr = stderr;
        }
    }
}
