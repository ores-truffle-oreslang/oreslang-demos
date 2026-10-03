# Web server demo

The web application is authored in exactly three Oreslang files:

1. `index.ores`
2. `health.ores`
3. `WebServer.ores`

`WebServer.ores` is the application composition root. It defines the route manifest by combining response bodies from the other two Oreslang files.

Run:

```bash
bash run.sh
```

Then open:

- `http://127.0.0.1:8080/`
- `http://127.0.0.1:8080/health`

Set `PORT` to change the listener port. Set `ORESLANG_COMPILER` if the compiler launcher is not on `PATH`.

The script stitches all three Oreslang files into one securely-created temporary source unit. `HttpHost.java` is intentionally generic: it owns only the JDK HTTP socket/listener boundary and consumes the route manifest emitted by `WebServer.ores`. Route paths, content types, and response bodies are not hard-coded in Java.

The host binds only to `127.0.0.1`, bounds guest runtime/output, drains stdout and stderr concurrently, validates route/header fields, limits route count, rejects invalid ports, and emits `X-Content-Type-Options: nosniff`.
