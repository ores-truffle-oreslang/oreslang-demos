# Desktop app demo

This demo keeps the application copy in Oreslang and uses a minimal Swing shell to provide the native window that the current guest API does not yet expose.

Run:

```bash
bash run.sh
```

The shell launches `app.ores` with the platform matching the host OS, captures the guest's stdout, and renders it in a desktop window.

You can validate the Oreslang source independently:

```bash
oreslang check app.ores
```

Set `ORESLANG_COMPILER` if `oreslang-compiler` is not on `PATH`.
