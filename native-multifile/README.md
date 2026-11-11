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
| Leaked alias | `module/alias-leak.atto` | Reject unaliased `transport_contract.Request` **at compile time** |
| Ambiguous function import | `negative/ambiguous-import.atto` and `conflicts.atto` | Reject an exported name provided by two modules |
| Conflicting mutable borrows | `negative/ownership-conflict.atto` | Reject simultaneous `rt mut borrow` loans of the same owner |
| Distinct mutable borrows | `negative/ownership-valid.atto` | Accept two independent owners and execute guest to produce `42` |

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
runner identity admission. `scripts/test-atto-negative-oracle.sh` supplies
synthetic compiler/Maven logs to prove the **oracle fails closed** against
unrelated infrastructure errors, wrong source locations, timeouts, misleading
exit codes, and guest stdout. **They never compile or execute AttoLang**.

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
the exact compiler via Maven, resolves its pinned runtime dependency classpath,
then invokes `dev.oreslang.launcher.OresMain` in a **separate JVM process**
so Maven plugin failures cannot be mistaken for guest diagnostics. It checks output and four negative compile-time failure cases with specific,
anchored compiler diagnostics, and records demo/compiler Git heads and trees,
source and artifact SHA-256 hashes, exact phase/exit codes, and per-case output.
An exit code of `1` alone does **not** make a negative test pass, and an
unrelated Maven or classpath error cannot satisfy the source-specific oracle. A successful
Maven build **alone** is never a guest-execution pass.

The `native-multifile.yml` workflow's public PR job is source-only. Its
opt-in self-hosted guest job only admits `workflow_dispatch` from an
**exact reviewed main SHA**. This prevents an unreviewed PR from obtaining
arbitrary execution on a trusted private-compiler runner. Before merge,
independent maintainers may run the documented exact-head guest script on an
authorized isolated runner and attach the resulting receipts for review.

## Runtime classpath supply-chain audit

The trusted Java runner now invokes `scripts/atto-runtime-classpath-audit.sh`
between its clean Maven build and any guest execution. The audit requires one
bounded ASCII classpath record with nonempty entries, canonical absolute JAR
paths, no symlinks (including path aliases), no duplicate entries, and no
injected control bytes. It SHA-256 hashes each runtime JAR and every compiled
class-file/tree member. The test job fails closed on malformed Maven output;
a JAR hash is **identity evidence**, not a signature or proof of trust.

`scripts/test-atto-runtime-classpath-audit.sh` exercises two synthetic
well-formed classpaths and sixteen adversarial malformed cases, without any
private AttoLang source or Maven dependencies. The existing negative
diagnostic oracle similarly runs host-only mutation tests; neither test
exercises actual guest linking.

## Cross-organization CI boundary

The Java compiler is private. Its checked-in
`docs/security/CI_PRIVATE_SOURCE_MIRRORING.md` requires approved destination
identity, protected source main and independent security-owner attestation
before **any** private source-bearing transfer. Current source-main reports
`protected: false`, so this qualification does **not** mirror compiler blobs
to another organization, even if that organization has working Actions runners.

An alternate-org **source-free** carrier may mirror exact SHA-identical public
checker scripts and run their host-only tests. Keep that evidence separately
labeled `NOT_EXECUTED` for the compiler guest. Never substitute source-free
runners or copied fixture text for a compiler-backed guest receipt.

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

## Known remaining limitations

This runner is a **candidate**, not completed guest evidence. The compiler's
`--check` diagnostics have not been executed at the pinned source head in this
repo. The oracle intentionally requires phase-specific error messages and may
remain red until the compiler emits the documented diagnostics. In particular,
a module alias that is accepted by typechecking but fails later in the
runtime **must not** be treated as an acceptable compile-time rejection.

The runner does not prove production-grade sandbox isolation, package artifact
signing, direct AOT native executable output, or independent LLVM/.NET/Wasm/Forge
parity. Do not promote the PR until exact-head guest receipts and independent
review are available.
