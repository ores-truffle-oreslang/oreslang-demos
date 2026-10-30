# Demo verification and release gate

This document is a review checklist for this repository, not a statement that CI or native guest execution has passed. Snapshot: 2026-10-29. Reconcile with the latest branch and toolchain before promotion.

## Scope

CLI, desktop, web and Java interop.

## Required verification

Run the individual `run.sh` scripts, `scripts/test-stitch.sh`, and the host contract checks with a known compiler; retain generated-source boundaries.

For every candidate release, record (1) demo Git commit SHA, (2) exact Oreslang compiler source SHA and executable digest, (3) backend and target profile, (4) commands and observed exit/stdout/stderr, (5) actual CI runner name, executed steps, and job conclusion. Use an explicit `NOT_EXECUTED` state for missing compiler, zero-step runs, skipped checks or unprovisioned runners; none is evidence of a passing guest test.

## Runtime and security boundaries

Multi-file sources are stitched into a temporary source unit; this is not proof of cross-file runtime linking.

Test positive and negative paths, malformed input, bounded capacity/backpressure, stop/close and stale-generation behavior where applicable. Never elevate a documentation-only/static contract test into a verified runtime feature. Keep permissions least-privilege and credentials out of fixtures.

## Integration policy

- Keep demo logic in native `.ores` wherever the demo promises native semantics; distinguish host adapters from guest behavior.
- Preserve each repository's existing compiler pins and documented syntax until compiler-backed tests justify changing them.
- Do not silently mirror private code to another organization. Cross-organization CI requires an approved private destination, approved policy, exact-tree/blob verification and no source secrets.
- Require independent review and executed exact-head checks before merging production-facing behavior. This checklist itself does not certify any such gate.
