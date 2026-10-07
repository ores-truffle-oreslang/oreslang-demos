# Compiler PR compatibility checkpoint — 2026-10-06

**Component:** Runnable host integrations: CLI, desktop, Java interop and web server.

Compiler source PRs **all open** at review: [#398](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/398), [#399](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/399), [#404](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/404), [#405](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/405), [#406](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/406), [#408](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/408), [#409](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/409), [#410](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/410), [#411](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/411), [#412](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/412).

## Integration dependency constraints

- `do select` stack: #405 -> #406 -> #408 -> #412; do not compile downstream tests against only one stack head.
- `do match` #404 is itself on a match feature branch; #398 is a separate map/exhaustiveness proposal.
- Actor isolation #399, SelectPlan #409, task-safe channels #410 and orthogonal binding qualifiers #411 are separate feature changes.
- Keep all current compiler pins, public exports, baseline files and default test behavior stable until exact source SHAs pass.

## oreslang-demos-specific tests and hardening

- Keep default host demos pinned to current compiler; new select/match examples require opt-in compiler branch (#398/#404/#405).
- Do not pass Java object references or guest callables through serialized actor mailbox boundaries (#399/#410/#411).
- Never treat do nb select's detached arm as returning a future value directly; model detached completion separately (#406/#412).
- Before updating demo shell runners, test Java/Truffle interop, desktop, CLI and server scenarios with exact upgraded compiler head.

## Verification gate

- Expected baseline check: `Run existing .github/workflows/host-shells.yml matrix`. This PR does **not** claim that check has been run.
- Add exact-head branch-specific integration tests before feature rollout. Negative tests must reject callable-bearing mailbox payloads, unsafe actor aliases, and discarded-return scope leaks.
- `const` is fixed readonly; `val` is fixed mutable (`const mut`); `let` is rebindable readonly; `let mut` is rebindable mutable, subject to borrow checking.
- Public Oreslang should use `rt copy`, `rt borrow`, `rt take`, `rt share` (and checked `rt proxy`) rather than `&`/`*` pointer syntax.
- If CI has no runner (runner ID zero, steps empty), no result was executed. Mirror the exact source tree to an organization with available GitHub Actions minutes, validate tree/blob hashes, and retain proof of executed jobs. Do not propagate secrets to the test org.

This checklist documents required follow-up **without pretending unmerged compiler semantics are available on main**.
