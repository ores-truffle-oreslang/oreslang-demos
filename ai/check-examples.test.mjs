import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { gitBlobSha, validateManifestShape } from "./check-examples.mjs";

const manifest = JSON.parse(readFileSync(new URL("./examples.manifest.json", import.meta.url), "utf8"));
const edited = () => structuredClone(manifest);

test("valid historical fixture manifest has only unverified sources", () => {
  const paths = validateManifestShape(manifest);
  assert.equal(paths.size, 11);
  assert.equal(gitBlobSha(Buffer.from("hello\n")), "ce013625030ba8dba906f756967f9e9ca394464a");
});

test("rejects forged compiler evidence even with a plausible commit", () => {
  const data = edited();
  data.examples[0].verification.status = "verified";
  data.examples[0].verification.compiler_commit = "a".repeat(40);
  data.examples[0].verification.backend = "java-graalvm";
  assert.throws(() => validateManifestShape(data));
});

test("rejects directory traversal, duplicates, and changed source identities", () => {
  const traversal = edited();
  traversal.examples[0].path = "../.github/workflows/host-shells.yml";
  assert.throws(() => validateManifestShape(traversal));

  const duplicate = edited();
  duplicate.examples[1].id = duplicate.examples[0].id;
  assert.throws(() => validateManifestShape(duplicate), /duplicate example id/);

  const mismatch = edited();
  mismatch.examples[0].source.commit = "f".repeat(40);
  assert.throws(() => validateManifestShape(mismatch));
});

test("rejects unsupported inventory statuses and synthetic source kinds", () => {
  const bypass = edited();
  bypass.examples[0].compatibility = "current-supported";
  assert.throws(() => validateManifestShape(bypass));
  const kind = edited();
  kind.generated_from.kind = "compiler-test-passed";
  assert.throws(() => validateManifestShape(kind));
});
