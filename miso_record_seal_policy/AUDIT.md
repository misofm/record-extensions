# Security review — `miso_record_seal_policy`

**Date:** 2026-08-31

**Scope:** `sources/policy.move`, its dependency assumptions, and the Seal evaluator
contract

## Security claim

A successful Seal evaluation of
`policy::seal_approve<T>(id, gate, record)` establishes that the session-key signer
currently owns a key-only `Record<T>` for the release encoded in `id`, and that `T` is
the original-ID certificate type authorized by the exact immutable gate encoded in
the same identity.

The claim depends jointly on:

- the record core omitting `store` and exposing no share or freeze function;
- exact gate object ID, original certificate type, and record `release_id` checks;
- Seal `ValidPtb` rejecting non-input arguments and non-`seal_approve*` commands; and
- key servers resolving object inputs to their latest on-chain versions and evaluating
  with normal sender/owner input validation.

The private `entry` modifier is defense in depth and upgrade guidance. It is not, by
itself, proof of current ownership.

## State and authority

- `CertificateGate` is key-only and created only inside this module. Every production
  creation path freezes it immediately, so the gate ID and stored `TypeName` are
  permanent and globally readable.
- `PolicyAdminCap` is key-only. An external package cannot share or freeze it to turn
  `&PolicyAdminCap` into public authority. The module exposes address transfer and a
  private entry that creates and freezes gates.
- The init gate authorizes
  `miso_pressing::certificate::Certificate`. Later gates store
  `type_name::with_original_ids<T>()`, preserving type identity across compatible
  upgrades of a trusted certificate package.
- Adding a gate only authorizes identities that explicitly embed that new gate ID. It
  cannot reinterpret an existing ciphertext identity.

## Identity validation

The identity is raw `[u8, u8, address, address, 32 bytes]`, exactly 98 bytes. Approval:

1. rejects fewer than 98 bytes before using the BCS reader;
2. peels schema, policy kind, gate address, release address, and a 32-byte `u256` nonce;
3. rejects any remainder, including a 99th trailing byte; and
4. checks schema `1`, release-mix kind `1`, exact gate ID, exact original certificate
   type, and exact record release.

The public builder separately rejects non-32-byte nonces. Randomness cannot be proven
on chain and remains an encryptor obligation.

## Side effects

`seal_approve` takes `&CertificateGate` and `&Record<T>`, returns nothing, emits no
event, and performs no write. Unit tests snapshot both object IDs and all readable
record/gate fields across a successful call.

## Deployment trust boundary

Miso's publication procedure consumes the fresh `UpgradeCap` for the policy and for
both packages in its trust closure:

- `miso_record`: an upgrade could add a share/freeze or alternative transfer path and
  invalidate the current-owner argument;
- `miso_pressing`: an upgrade could widen construction of the trusted original-ID
  `Certificate` type; and
- `miso_record_seal_policy`: an upgrade could change the approval predicate itself.

Applications pin the reviewed policy package, frozen gate, chain, and committee and
reject descriptor-selected alternatives. They do not claim to prove global absence of
an `UpgradeCap`: Sui exposes no general Move predicate for that fact, and an
address-scoped RPC census would not be a proof because a cap can move or be wrapped.
Immutability of Miso's deployed Record, Pressing, and policy packages is therefore an
explicit operator/customer trust assumption. An on-chain attestation would require a
separate trusted off-chain mechanism such as Nautilus and is outside this launch.

## Residual assumptions

- Seal threshold/key-server integrity and full-node freshness remain external trust
  assumptions.
- A holder can retain a key already fetched. Fresh random 32-byte nonces prevent them
  from predicting identities for future encrypted material; they do not revoke keys
  already released.
- Whoever controls `PolicyAdminCap` decides which new certificate types may authorize
  newly created identities. Cap custody must match that governance role.
- Admin-cap transfer is one-step and irreversible. Operational procedure must verify
  the recipient address before signing; loss only prevents adding future gate types.

## Verification

Move tests cover init/freeze behavior, later gate addition, admin-cap transfer, exact
golden bytes, successful side-effect-free approval, wrong type/gate/release, wrong
schema/kind, short and trailing identities, and invalid nonce length.
