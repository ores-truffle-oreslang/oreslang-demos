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

The host bounds guest runtime/output, drains stdout and stderr concurrently, and validates title and window dimensions before creating a native window.

Set `ORESLANG_COMPILER` if `oreslang-compiler` is not on `PATH`.
