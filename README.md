# AttoLang demos (`oreslang-demos`)

Runnable example applications for **AttoLang**, formerly called Oreslang.

This repository keeps the historic `oreslang-demos` path, `.ores` fixtures, Java class names and `oreslang` command names while their actual toolchain migration is tested. New language source and examples should use `.atto` once the selected compiler accepts it. Do not rename existing source files without updating launchers, host integrations and executable tests.

## Layout

- `cli/` — a pure AttoLang command-line application assembled from three `.ores` files.
- `desktop-app/` — a native desktop host whose application title, size, and content are defined by four AttoLang files.
- `web-server/` — a local HTTP host whose route table, content types, and response bodies are defined by three AttoLang files, with `WebServer.ores` as the composition root.
- `interop/` — mixed Java/AttoLang source demos in both directions.

## Requirements

- `oreslang-compiler` on `PATH`, or set `ORESLANG_COMPILER=/path/to/oreslang-compiler`.
- A JDK for the small desktop/window and HTTP-listener host adapters.
- Optional: the public `oreslang` CLI for non-executing checks.
- For the in-process Java -> AttoLang embedding demo, set `ORESLANG_SOURCE_DIR` to a local checkout of `oreslang-source.java` (or provide `ORESLANG_CLASSPATH` directly).

## Multi-file demos

The current runtime can execute a single source unit reliably, while runtime cross-file linking is still being hardened. These demos therefore make the source-unit boundary explicit: each `run.sh` concatenates its ordered `.ores` files into one temporary `.ores` program before execution.

That keeps the examples genuinely multi-file at authoring time without hiding application logic in Java or depending on an unfinished runtime linker.

The Java files that remain are deliberately generic capability adapters:

- `desktop-app/DesktopHost.java` owns only the Swing/native-window boundary.
- `web-server/HttpHost.java` owns only the JDK HTTP-listener boundary.

The actual demo configuration, routes, content types, copy, math, and response bodies live in AttoLang.

## Java / AttoLang interop

`interop/JavaEmbedsOreslang.java` contains an AttoLang program directly in a Java text block and evaluates it in-process through Graal Polyglot. This is true Java-hosted AttoLang execution; it does not spawn the AttoLang CLI.

`interop/OreslangEmbedsJava.ores` demonstrates the reverse source direction using the runtime surface available today: an AttoLang program owns and emits Java source, which the host script then runs with Java source-file mode. This is build-time/code-generation interop, not unrestricted guest reflection.

Direct AttoLang -> Java object/method calls should use a future capability-gated host-binding API with explicit exports. The demos intentionally do not pretend that unrestricted `Java.type()`-style host access exists.

## 2026-10-06 compiler PR compatibility

For the October 6, 2026 upstream compiler PR checkpoint, see [docs/compiler-pr-sync.md](docs/compiler-pr-sync.md). These features remain unmerged; this repo preserves its existing compiler reference and defaults until exact-SHA integration evidence is available.
