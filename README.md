# Oreslang demos

Runnable example applications for Oreslang.

## Layout

- `cli/` — a pure Oreslang command-line application assembled from three `.ores` files.
- `desktop-app/` — a native desktop host whose application title, size, and content are defined by four Oreslang files.
- `web-server/` — a local HTTP host whose route table, content types, and response bodies are defined by three Oreslang files, with `WebServer.ores` as the composition root.

## Requirements

- `oreslang-compiler` on `PATH`, or set `ORESLANG_COMPILER=/path/to/oreslang-compiler`.
- A JDK for the small desktop/window and HTTP-listener host adapters.
- Optional: the public `oreslang` CLI for non-executing checks.

## Multi-file demos

The current runtime can execute a single source unit reliably, while runtime cross-file linking is still being hardened. These demos therefore make the source-unit boundary explicit: each `run.sh` concatenates its ordered `.ores` files into one temporary `.ores` program before execution.

That keeps the examples genuinely multi-file at authoring time without hiding application logic in Java or depending on an unfinished runtime linker.

The Java files that remain are deliberately generic capability adapters:

- `desktop-app/DesktopHost.java` owns only the Swing/native-window boundary.
- `web-server/HttpHost.java` owns only the JDK HTTP-listener boundary.

The actual demo configuration, routes, content types, copy, math, and response bodies live in Oreslang.
