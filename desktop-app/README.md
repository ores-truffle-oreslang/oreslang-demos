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

The script stitches the four Oreslang files into one temporary program, runs it, and passes the resulting application manifest to the native host.

Set `ORESLANG_COMPILER` if `oreslang-compiler` is not on `PATH`.
