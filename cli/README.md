# CLI demo

A pure Oreslang command-line program assembled from exactly three source files:

1. `math.ores`
2. `messages.ores`
3. `main.ores`

Run:

```bash
bash run.sh
```

`run.sh` stitches the three files into one temporary source unit and executes it with `oreslang-compiler`.

Expected output ends with `42`.
