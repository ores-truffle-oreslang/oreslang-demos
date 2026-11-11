# Native multi-file AttoLang demo (opt-in)

This is a **new, independent** compiler-backed qualification path. It does not
modify the 11 historical `.ores` inventory fixtures, `SOURCE_REF`, the
existing stitched examples, or their behavior.

## What is being tested

| Case | Source boundary | Expected compiler-backed behavior |
| --- | --- | --- |
| Linked function | `src/main.atto` imports `./math` | Execute real linked guest, output exactly `42` |
| Qualified class | `module/main.atto` imports module `tc` from `contract.atto` | Resolve `tc.Request`, output exactly `42` |
| Missing import | `negative/missing-helper.atto` | Reject unresolved relative source |
| Leaked alias | `module/alias-leak.atto` | Reject unaliased `transport_contract.Request` |

The module-qualified class test intentionally exercises a compiler behavior
that has had upstream guest-resolution problems. A failed test is a useful
parity blocker, **not** permission to replace the import with a copied source
or change the expected output.

The compiler must load the entry `.atto` and follow imports itself. There is
**no `stitch-ores.sh` invocation and no concatenation fallback**. The
`.atto.pkg.toml` file declares project roots and standard-library profile.
File-level project configuration is distinct from source-level module aliases.

## Source and backend pin

`JAVA_COMPILER_REF` is a separately reviewed, opt-in candidate snapshot of
the **private** `ores-truffle-oreslang/oreslang-source.java` compiler:
`6d8eb70048eafc9a84c5aebe9c1bb06104f16e76` (observed main 2026-11-08).
It is **not** a claim that these fixtures passed at that head, nor an update
to the historical `SOURCE_REF`.

The Java/Graal execution mode used by the initial runner is
`server-jit`. Java **Native Image AOT** and LLVM/.NET/Wasm/Forge parity require
distinct exact-binary runs and are **NOT_EXECUTED** here.

## Structural checks without a compiler

```bash
bash scripts/test-native-multifile-policy.sh
bash ci/test-source-policy.sh
```

These run with a public GitHub-hosted runner on PRs. They verify file
integrity, canonical suffixes, no symlinks, no source stitching, and fail-closed
runner identity admission; **they never compile or execute AttoLang**.

## Exact Java/Graal guest execution (trusted runner only)

Use a trusted isolated Linux runner with JDK 25, Maven, coreutils, a clean
checkout of the **private** Java source repo at `JAVA_COMPILER_REF`, and
an authorized exact demo checkout. For example:

```bash
export ATTO_JAVA_SOURCE_DIR=/path/to/approved/oreslang-source.java
export ATTO_EXPECTED_DEMO_SHA="$(git rev-parse HEAD)"
export ATTO_RECEIPT_DIR=/path/to/secure/evidence
bash scripts/run-native-multifile-java.sh
```

The runner rejects mismatched/dirty source trees, malformed commit IDs,
symlinked receipt directories, and unsafe Maven argument paths. It builds
the exact compiler via Maven, invokes entrypoint `.atto` files, checks output
and negative import failures, and records demo/compiler Git heads and trees
plus compiler artifact SHA-256 hashes and per-case output. A successful
Maven build **alone** is never a guest-execution pass.

The `native-multifile.yml` workflow's public PR job is source-only. Its
opt-in self-hosted guest job only admits `workflow_dispatch` from an
**exact reviewed main SHA**. This prevents an unreviewed PR from obtaining
arbitrary execution on a trusted private-compiler runner. Before merge,
independent maintainers may run the documented exact-head guest script on an
authorized isolated runner and attach the resulting receipts for review.

## Evidence policy

Do not mark this example verified unless the **exact demo PR head** and
**exact compiler source/binary** have matching guest receipts, a non-zero
recorded count of executed runner steps, tested output/error assertions,
and independent review. A skipped or zero-step CI job is a runner-admission
failure/NOT_EXECUTED. Host-only checks never prove native linking, actor
semantics, AOT compilation, or other backend parity.

Never mirror private compiler source into another organization without
explicit source-transfer authorization and verified security controls. A
source-free canary is not a guest execution receipt.

Related: [historical exact-compiler inventory issue #9](https://github.com/ores-truffle-oreslang/oreslang-demos/issues/9)
and [native multi-file qualification issue #47](https://github.com/ores-truffle-oreslang/oreslang-demos/issues/47).
