# Oreslang public demo provenance and evidence boundary

The `ai/examples.manifest.json` inventory identifies an **historical source commit**, not the current compiler version. It intentionally does not state that the examples compile.

## Checks performed

`node ai/check-examples.mjs` now requires:

1. Exactly one full 40-character source commit SHA for every manifest item.
2. A local Git checkout containing that commit, which must be an ancestor of the checked-out HEAD.
3. An exact match between the inventory and **all** .ores demo paths in the pinned Git commit tree.
4. Exact byte-for-byte equality between each current file and `git show SOURCE_COMMIT:path`.
5. Agreement between the Git blob SHA declared for each file and the historical bytes.
6. No symlinks, unexpected file paths, duplicate entries, or unsupported evidence states.

This proves that the inventory's historical **source bytes really occur in the named Git commit**. It still does not prove a compiler accepts or executes the programs. SHA-1 Git object IDs are used to match the repository's Git object format, not as a claim of collision-resistant cryptographic signing.

## Running checks

For a new checkout, fetch complete history (GitHub Actions uses `fetch-depth: 0`) and run:

```sh
node --test ai/check-examples.test.mjs
node ai/check-examples.mjs
```

If the pinned historical commit is missing because of a shallow clone, the check must **fail closed**, not silently switch to validating only the working tree.

If a current demo changes, the maintainer must deliberately create a new immutable **source snapshot commit**, review the changed files, and update all manifest paths/blob hashes/source-commit fields together. Never silently rewrite the old commit. An upstream source-commit verification is not a substitute for an approved compiler run.

## Later compiler validation

An independent real-compiler gate should report source commit, compiler repository commit and executable digest, backend/target, toolchain version, argv, exit status, stdout/stderr, fixture hash, expected behavior, and evidence URL. That gate must distinguish parse-only, typecheck, compilation, runtime test and cross-backend equivalence. It must not publish private compiler files, tokens or logs containing secrets.

Until a separately reviewed evidence schema and authenticated runner exist, this inventory rejects **all** promotion to `verified`.
