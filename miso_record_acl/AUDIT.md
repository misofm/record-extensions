# Security Audit — `miso_record_acl`

**Revision:** not a git repository (working tree as of audit date) · **Date:** 2026-08-23 ·
**Toolchain:** sui 1.77.2

Audit of `miso_record_acl`, the Seal decryption policy gating encrypted
material (liner notes, stems, sessions) on holding a `Record`. Verdict:
**safe — no findings.** The fail-open risks the module doc warns about are
all closed in code; the residual risks are verifier-configuration issues
documented in-module.

## What it does

Three private `entry` approvals (`acl.move:187`, `:204`, `:222`), one per
subject kind (release / recording / composition), each a chain of links:
sender owns record (by-value input, enforced by the chain's input checker) →
record is a copy of release → release carries the recording → recording is of
the composition (type-level). The subject is pinned to the Seal identity via
`subject_of` so a record for one release cannot open another's material.

Threat model: a listener opening material they didn't buy; identity
substitution (presenting record for A, asking key for B); replay via shared
or conjured records; truncated/padded identity parsing.

## Why the fail-open paths are closed

- **Link 1 (ownership) — by value, private entry.** Each `seal_approve_*`
  takes `record: Record` BY VALUE (`:189`, `:206`, `:224`). A shared record
  cannot be passed by value; an immutable one cannot either; a record owned
  by someone else fails the fullnode's input ownership check. `entry` +
  private means a PTB cannot feed in the result of another Move call — the
  record must be a direct owned-object input, so nothing can be conjured
  mid-transaction. The module documents the residual operational requirement:
  the verifier must simulate with owner checks ON (gRPC `SimulateTransaction`
  default, `dryRun`) — `devInspect` with `skipChecks: true` would silently
  drop link 1 (`:58-69`). That is a key-server configuration requirement, not
  a code defect.
- **Subject pinning.** `seal_approve_release` asserts
  `subject_of(id) == object::id(release)` (`:193`); `seal_approve_composition`
  pins the composition (`:230`); `seal_approve_recording` reads the subject
  OUT of the identity (`:210`) since no recording object is presented. Every
  entry's subject is checked against the identity, so the granted key is
  always for the material the presented chain actually reaches.
- **Identity parsing is strict.** `subject_of` (`:127`) peels exactly
  `[address ‖ vec<u8> nonce]` and asserts zero remainder
  (`EMalformedIdentity`, `:131`) — no truncated or trailing-bytes identities.
- **Link 4 is a real proof, not a hint.** Verified at the pinned
  dependencies: `composition::new` consumes the `TreasuryCap` and requires
  zero supply via `share::initialize`
  (`dependencies/miso/composition.move:171-203`), so one share type = one
  composition forever; `recording::new` takes `&Composition<CompositionShare>`
  (`dependencies/miso/recording.move`), binding the phantom pair at creation.
  Hence `Recording<_, S>` + `Composition<S>` in one call really does mean
  "this recording is of this composition" — and taking the composition BY
  OBJECT (`:227`) prevents the caller from lifting `CompositionShare` off the
  recording's own type, which would vacuate the check (`:161-167`).
- **No side effects.** Approvals self-transfer the record back to the sender
  (`:195`, `:211`, `:232`); real executions are no-ops, simulations read only
  status. Distinct abort codes per failure keep verifier logs meaningful
  (`:91-103`).

## Findings

None in code. Two documented operational requirements bear repeating:

- **Nonce discipline** (`:107-116`): Seal derives one key per identity; a
  predictable nonce lets a current record holder prefetch keys for FUTURE
  material and keep them after selling the record. Encrypters MUST use a
  random nonce per encryption.
- **Verifier must keep owner checks on** (see above).

## Edge cases (verified)

- Wrong release for record — `EWrongRelease` (tests :228, :249).
- Recording not on release — `ERecordingNotOnRelease` (tests :195, :267).
- Identity subject ≠ presented object — `EWrongSubject` (tests :289, :308).
- Malformed/trailing identity — `EMalformedIdentity` (tests :75, :338).
- Shared record presented by value — rejected by the transaction input layer
  (cannot pass a shared object by value).
- Cross-release recording overlap — a record for ANY release carrying a
  qualifying track grants access; documented as intended (`:79-82`).

## Verification

7 unit tests (`tests/acl_tests.move`) covering all three approvals and every
abort gate, through the `#[test_only]` wrappers (`:240-268`) since the
entries are private. Cross-read: `miso_record::record` (by-value/store
semantics), `miso::{composition, recording, release}` pinned build copies
(`contains_recording` at `release.move:340-342` is a linear scan over ≤ 255
tracks — bounded, no DoS).
