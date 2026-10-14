#!/usr/bin/env node
// Inventory integrity checker, NOT an Oreslang compiler or language conformance test.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const fullSha = /^[0-9a-f]{40}$/;
const normalizedPath = /^(cli|desktop-app|web-server|interop)\/[A-Za-z0-9_-]+\.ores$/;
const sourceRepo = "ores-truffle-oreslang/oreslang-demos";

function gitBlobSha(contents) {
  return createHash("sha1")
    .update(Buffer.from("blob " + contents.length + "\0"))
    .update(contents)
    .digest("hex");
}

async function main() {
  const data = JSON.parse(await readFile(path.join(root, "ai/examples.manifest.json"), "utf8"));
  assert.equal(data.schema_version, 1);
  assert.equal(data.generated_from.repository, sourceRepo);
  assert.match(data.generated_from.source_commit, fullSha);
  assert.ok(data.warning.includes("NOT compiler-verified"), "explicit status warning required");
  assert.ok(Array.isArray(data.examples) && data.examples.length > 0);

  const paths = new Set();
  const ids = new Set();

  for (const entry of data.examples) {
    assert.match(entry.id, /^[a-z][a-z0-9-]+$/);
    assert.ok(!ids.has(entry.id), "duplicate example id: " + entry.id);
    ids.add(entry.id);
    assert.match(entry.path, normalizedPath, "allowlisted source path");
    assert.ok(!paths.has(entry.path), "duplicate example path: " + entry.path);
    paths.add(entry.path);

    assert.equal(entry.source.repository, sourceRepo);
    assert.equal(entry.source.commit, data.generated_from.source_commit);
    assert.match(entry.source.blob_sha, fullSha);

    // This phase never silently upgrades an entry to "verified": real compiler
    // validation must be added to the exact-commit conformance pipeline.
    assert.equal(entry.compatibility, "legacy-or-unassessed");
    assert.deepEqual(entry.verification, {
      status: "not-run",
      backend: null,
      compiler_commit: null,
      command: null,
      evidence: null,
    });

    const bytes = await readFile(path.join(root, entry.path));
    assert.equal(gitBlobSha(bytes), entry.source.blob_sha, "stale source: " + entry.path);
  }

  const actual = [];
  for (const folder of ["cli", "desktop-app", "interop", "web-server"]) {
    for (const name of await readdir(path.join(root, folder))) {
      if (name.endsWith(".ores")) actual.push(folder + "/" + name);
    }
  }
  actual.sort();
  assert.deepEqual([...paths].sort(), actual, "every public .ores demo must be inventoried");
  process.stdout.write(
    JSON.stringify({
      inventory: "ok",
      pinned_source_commit: data.generated_from.source_commit,
      source_integrity_checked: paths.size,
      compiler_verified: 0,
      backend_parity_verified: false,
    }) + "\n",
  );
}

main().catch((error) => {
  console.error("Example inventory rejected:", error.message);
  process.exitCode = 1;
});
