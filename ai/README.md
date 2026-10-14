# Oreslang example inventory for AI assistants

This is an **integrity-checked inventory of 11 existing public demonstration files**. It is not a language specification, compiler test result, compatibility promise, or training dataset license grant.

The inventory at [examples.manifest.json](examples.manifest.json) pins all entries to public Oreslang demos commit `6fd8930e167ff6dbd372a15cd1049427df69569b`. The `blob_sha` field is the Git object identity for each source file. Run:

```sh
node ai/check-examples.mjs
```

This verifies manifest shape, all declared source blobs, allowlisted paths, unique IDs, and complete coverage of the demo files. It **does not parse, compile, run, or typecheck Oreslang**. Every entry has `verification.status: "not-run"`; the checker rejects a claim of compiler verification without a separate evidence pipeline.

## Using these examples safely

1. Retrieve the released language specification and compiler/backend identity for the project you are editing.
2. Check the example's `compatibility` and `verification` properties. Current examples are historical; older `routine ... =>` or `fnc ... =>` syntax may need changes.
3. Verify the sample with the selected compiler. Do not convert a Git blob hash into a claim that the source compiles.
4. Use an actual conformance runner (for example, the private `oreslang-platform-conformance` test harness) to generate evidence containing exact compiler binary identity, CLI command, test source, exit status, stdout and stderr, and platform/backend.
5. Keep negative and unsupported examples explicitly labeled; absence of a compiler test is not a passing test.

## Promotion criteria

Do not change `not-run` to `verified` merely because a Markdown check, static source hash check, GitHub Actions workflow, or a mocked compiler succeeded. A future version of this schema may admit `verified` only with real, attributable compiler runs and a CI-reviewed evidence artifact. Until then, the schema intentionally fails closed.

The published [Oreslang AI language reference](https://ores-truffle-oreslang.github.io/language/) describes the public reference status and links to these historical demos.
