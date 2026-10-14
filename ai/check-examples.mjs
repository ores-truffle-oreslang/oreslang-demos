#!/usr/bin/env node
// Historical source provenance verifier. This is NOT an Oreslang compiler test.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const fullSha = /^[0-9a-f]{40}$/;
const normalizedPath = /^(cli|desktop-app|web-server|interop)\/[A-Za-z0-9_-]+\.ores$/;
const sourceRepo = "ores-truffle-oreslang/oreslang-demos";
const folders = ["cli", "desktop-app", "interop", "web-server"];

function git(args, encoding) {
  return execFileSync("git", args, { cwd: root, encoding, maxBuffer: 4 * 1024 * 1024 });
}

export function gitBlobSha(contents) {
  return createHash("sha1")
    .update(Buffer.from("blob " + contents.length + "\0"))
    .update(contents)
    .digest("hex");
}

export function validateManifestShape(data) {
  assert.equal(data.schema_version, 1);
  assert.equal(data.generated_from.repository, sourceRepo);
  assert.equal(data.generated_from.kind, "public-reviewed-demo-source");
  assert.match(data.generated_from.source_commit, fullSha);
  assert.equal(data.applicability, "historical-demo-sources; not a released language specification");
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
    // Even "verified" claims with plausible-looking evidence must fail here:
    // only a separately reviewed real-compiler evidence protocol may promote them.
    assert.equal(entry.compatibility, "legacy-or-unassessed");
    assert.deepEqual(entry.verification, {
      status: "not-run",
      backend: null,
      compiler_commit: null,
      command: null,
      evidence: null,
    });
  }
  return paths;
}

async function main() {
  const data = JSON.parse(await readFile(path.join(root, "ai/examples.manifest.json"), "utf8"));
  const paths = validateManifestShape(data);
  const sourceCommit = data.generated_from.source_commit;

  // A declared commit SHA alone does not prove historical provenance. Verify
  // that Git has the commit, it is an ancestor, and it contains these exact
  // files with exactly the expected blobs. This needs a full-history checkout.
  git(["cat-file", "-e", sourceCommit + "^{commit}"]);
  git(["merge-base", "--is-ancestor", sourceCommit, "HEAD"]);
  const treePaths = git(["ls-tree", "-r", "--name-only", sourceCommit], "utf8")
    .trim().split("\n").filter((p) => normalizedPath.test(p)).sort();
  assert.deepEqual([...paths].sort(), treePaths, "inventory must cover the pinned commit's complete demo source tree");

  for (const entry of data.examples) {
    const fullPath = path.join(root, entry.path);
    const stat = await lstat(fullPath);
    assert.ok(stat.isFile() && !stat.isSymbolicLink(), "expected ordinary source file: " + entry.path);
    const current = await readFile(fullPath);
    const historical = git(["show", sourceCommit + ":" + entry.path]);
    assert.equal(gitBlobSha(historical), entry.source.blob_sha, "invalid historical blob SHA: " + entry.path);
    assert.deepEqual(current, historical, "working source differs from pinned commit: " + entry.path);
  }

  const actual = [];
  for (const folder of folders) {
    for (const name of await readdir(path.join(root, folder))) {
      if (name.endsWith(".ores")) actual.push(folder + "/" + name);
    }
  }
  assert.deepEqual([...paths].sort(), actual.sort(), "every working .ores demo must be inventoried");

  process.stdout.write(JSON.stringify({
    inventory: "ok",
    source_commit_attested_by_local_git_tree: sourceCommit,
    source_integrity_checked: paths.size,
    compiler_verified: 0,
    backend_parity_verified: false,
  }) + "\n");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error("Example inventory rejected:", error.message);
    process.exitCode = 1;
  });
}
