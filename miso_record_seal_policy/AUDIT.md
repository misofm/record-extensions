# Security review — `miso_record_seal_policy`

**Date:** 2026-09-02

**Scope:** `sources/policy.move`, Record dependency
`8a331e2880723aa0330dee00c55525aa6b4c1516`, Protocol dependency
`6de5f9881ee62c81c57ce16832efc24dc33ae429`, both Testnet and Mainnet lock graphs,
and the Seal evaluator contract.

## Finding and disposition

The former ownership claim is invalid after Record gained `store`.

An external caller may apply framework public ownership operations to a newly minted
Record. A shared or frozen Record can then be supplied as `&Record` by a non-owner.
Move exposes no general ownership-mode inspection inside `seal_approve`, and Seal's
dry-run cannot add an ownership predicate absent from the Move function.

Disposition: the policy fails closed. A well-formed, relationship-valid request aborts
with `EOwnershipUnprovable`; malformed or mismatched inputs retain their more specific
errors. No Recording-session key should be served by this revision.

## Preserved validation

The identity is raw `[u8, u8, address, address, 32 bytes]`, exactly 98 bytes. Before
the fail-closed abort, the policy:

1. rejects fewer than 98 bytes before invoking the BCS reader;
2. peels schema, kind, gate, Recording, and nonce;
3. rejects every trailing byte;
4. checks schema `1`, Recording-session kind `1`, and exact frozen gate;
5. checks that the supplied Release ID equals `record.release_id()`; and
6. checks that the identity's Recording appears in that Release's immutable tracklist.

The public builder rejects non-32-byte nonces. Randomness remains an encryptor
obligation.

## State and authority

- `RecordGate` is key-only; `init` creates one and freezes it immediately.
- Record creation is edition-local: a Pressing owns supply and authorizes the
  distributor witness consumed by `pressing::mint`. Authenticity remains distinct
  from current ownership.
- The production policy imports no Pressing API and holds no admin capability.
- A Recording-bound identity remains reusable across legitimate Releases containing
  that Recording; a test-only validator proves this relationship independently of the
  deliberately disabled ownership decision.

## Side effects

`seal_approve` takes immutable references, emits no event, returns nothing, and never
writes state. It validates identity and always aborts, satisfying Seal's side-effect-
free evaluation requirement.

## Adversarial verification

Thirteen Move tests pass under both `--build-env testnet` and `--build-env mainnet`.
They cover gate freezing, golden identity bytes, relationship validation across
distinct Releases, fail-closed matching requests, a non-owner attempting approval
with a shared Record, wrong gate, substituted Release, Recording outside the Release,
malformed/trailing identity bytes, and invalid nonce length. Test Records follow the
current production lifecycle: create a Release, derive its Pressing, authorize a
distributor witness, and mint through that Pressing. The production `policy` module
has literal 100% Move coverage.

External-package compiler probes reject both `RecordGate` construction and direct
calls to private `seal_approve`.

## Dependency graph

Record `8a331e28…` and this package both pin Protocol `6de5f988…`, which pins BPS
`4ca1972a…` and Share `561cfad9…`. The regenerated Testnet and Mainnet lock graphs
each contain exactly one Record, Protocol, BPS, Share, Sui, and MoveStdlib source.
No override or legacy suffixed dependency entry remains.

## Required redesign

Re-enabling access requires a proof whose lifecycle remains correct under Record
transfer, wrapping, sharing, and freezing. Candidate designs include a separately
transferred key-only access capability or a custody-specific relationship such as a
Kiosk plus its owner capability. A bare immutable Record reference must not be
restored as the proof.

Previously fetched keys remain usable; a new policy package cannot revoke material
already released by an older deployment.
