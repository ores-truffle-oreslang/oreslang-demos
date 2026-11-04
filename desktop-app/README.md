# Desktop app demo

The application is authored across four Oreslang files:

1. `title.ores`
2. `body.ores`
3. `window.ores`
4. `DesktopApp.ores`

Oreslang owns the application title, body text, width, and height. `DesktopHost.java` is only the generic Swing/native-window capability boundary that the current guest API does not yet expose directly.

Run:

```bash
bash run.sh
```

The script stitches the four Oreslang files into one securely-created temporary program, runs it, validates the manifest, and passes it to the native host.

For headless CI, the host exposes a validation-only mode:

```bash
java DesktopHost.java --manifest-only /path/to/stitched-app.ores
```

The host applies one monotonic **10-second end-to-end deadline** to compiler exit and both stdout/stderr captures (including compiler descendants that retain inherited pipe handles). It limits each stream to 1 MiB, fails immediately on an overflow, and avoids an unbounded executor join on teardown. Run `javac -Xlint:all desktop-app/DesktopHost.java desktop-app/DesktopHostContractTest.java && java -cp desktop-app DesktopHostContractTest` from the repository root to execute the clean-manifest and inherited-pipe adversarial acceptance tests. This host runs developer-selected compiler executables; it does **not** provide an OS sandbox or safely terminate detached descendants of arbitrary untrusted executables.

Set `ORESLANG_COMPILER` if `oreslang-compiler` is not on `PATH`.
