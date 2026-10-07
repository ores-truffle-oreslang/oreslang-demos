# Oreslang demos

Runnable example applications for Oreslang.

## Layout

- `cli/` — a pure Oreslang command-line application assembled from three `.ores` files.
- `desktop-app/` — a native desktop host whose application title, size, and content are defined by four Oreslang files.
- `web-server/` — a local HTTP host whose route table, content types, and response bodies are defined by three Oreslang files, with `WebServer.ores` as the composition root.
- `interop/` — mixed Java/Oreslang source demos in both directions.

## Requirements

- `oreslang-compiler` on `PATH`, or set `ORESLANG_COMPILER=/path/to/oreslang-compiler`.
- A JDK for the small desktop/window and HTTP-listener host adapters.
- Optional: the public `oreslang` CLI for non-executing checks.
- For the in-process Java -> Oreslang embedding demo, set `ORESLANG_SOURCE_DIR` to a local checkout of `oreslang-source.java` (or provide `ORESLANG_CLASSPATH` directly).

## Multi-file demos

The current runtime can execute a single source unit reliably, while runtime cross-file linking is still being hardened. These demos therefore make the source-unit boundary explicit: each `run.sh` concatenates its ordered `.ores` files into one temporary `.ores` program before execution.

That keeps the examples genuinely multi-file at authoring time without hiding application logic in Java or depending on an unfinished runtime linker.

The Java files that remain are deliberately generic capability adapters:

- `desktop-app/DesktopHost.java` owns only the Swing/native-window boundary.
- `web-server/HttpHost.java` owns only the JDK HTTP-listener boundary.

The actual demo configuration, routes, content types, copy, math, and response bodies live in Oreslang.

## Java / Oreslang interop

`interop/JavaEmbedsOreslang.java` contains an Oreslang program directly in a Java text block and evaluates it in-process through Graal Polyglot. This is true Java-hosted Oreslang execution; it does not spawn the Oreslang CLI.

`interop/OreslangEmbedsJava.ores` demonstrates the reverse source direction using the runtime surface available today: an Oreslang program owns and emits Java source, which the host script then runs with Java source-file mode. This is build-time/code-generation interop, not unrestricted guest reflection.

Direct Oreslang -> Java object/method calls should use a future capability-gated host-binding API with explicit exports. The demos intentionally do not pretend that unrestricted `Java.type()`-style host access exists.

## 2026-10-06 compiler PR compatibility

For the latest 10 upstream Oreslang compiler PRs, see [docs/compiler-pr-sync.md](docs/compiler-pr-sync.md). These features remain unmerged; this repo preserves its existing compiler reference and defaults until exact-SHA integration evidence is available.
