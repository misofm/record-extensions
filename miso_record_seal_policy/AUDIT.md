# Security review — `miso_record_seal_policy`

**Date:** 2026-09-01

## Security claim

A successful `policy::seal_approve(id, gate, record, release)` evaluation
establishes that the session-key signer currently owns the exact key-only Miso
`Record`, the supplied immutable `Release` is the one named by that Record, and
the Recording encoded in the exact 98-byte identity is a member of that
Release's immutable tracklist.

The identity is Recording-bound rather than Release-bound. This makes the same
canonical session accessible through every legitimate Release containing the
Recording and avoids a mutable list of per-Release key envelopes.

## Adversarial coverage

Move tests cover gate freezing, exact golden identity bytes, two distinct
Releases unlocking the same Recording identity, wrong gate, substituted Release,
Recording outside the Release, malformed/trailing identity bytes, and invalid
nonce length. Successful approval snapshots the borrowed object identities and
does not mutate them.

External compiler probes must additionally confirm that another package cannot
construct `RecordGate` or call private `seal_approve` directly.

## Residual assumptions

- Record Settings administration controls which issuers can mint the concrete
  Record format. Revocation prevents later mints but does not invalidate copies
  already created by an authorized witness.
- Recording administration can replace the public session pointer. Published
  Walrus bytes and a key already released remain recoverable to anyone who kept
  them; this is access gating, not retroactive DRM.
- Seal threshold/key-server integrity, Sui input freshness, and full-node
  availability remain external trust assumptions.
