# Security review — `record_seal_policy`

**Date:** 2026-09-02

**Scope:** `sources/policy.move`, Record dependency
`8ece285b087cecf2892a19bcb13a7360e92b2937`, and MusicOS dependency
`4fed48b2b5632122fb677d742881259c65b1bc78`.

## Policy surface

The package exposes exactly three non-public Seal entry functions:

- `seal_approve_composition`
- `seal_approve_recording`
- `seal_approve_release`

All take the requested identity as their first parameter, use only immutable
references, return nothing, and do not modify onchain state.

## Authorization checks

Every policy checks both of these Release bindings:

1. the identity's `release_id` equals the supplied Release object ID; and
2. `record.release_id()` equals that same ID.

Composition and Recording identities additionally contain a `u8` track index
and target object ID. Their policies check that the index is in bounds, that
the selected Track contains the target ID, and that the supplied Composition or
Recording has that exact object ID.

Identity lengths are checked before BCS peeling: 32 bytes for Release and 65
bytes for Composition or Recording.

## Accepted Record-reference semantics

The policy intentionally treats a usable `&Record` input as the entitlement.
This follows Sui input authorization for address-owned Records. Because Record
has `key + store`, an owner can also share or freeze it; a shared or frozen
Record can then be referenced by other callers and will satisfy this policy.
This behavior is accepted by design.

## Verification

Nine Move tests pass under both Testnet and Mainnet builds. They cover the three
successful approval paths, invalid track index rejection, and malformed Release
and track-member identities. Each policy also has a multi-transaction
substitution scenario with an address-owned Record and shared policy inputs,
matching the ownership shape of the Seal PTB.
