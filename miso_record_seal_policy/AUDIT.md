# Security review — `miso_record_seal_policy`

**Date:** 2026-08-31

**Scope:** `sources/policy.move`, the concrete Record dependency at `a235ffd`, and
the Seal evaluator contract.

## Security claim

A successful `policy::seal_approve(id, gate, record)` evaluation establishes that the
session-key signer currently owns the exact key-only Miso `Record` type for the
release encoded in `id`, and that the identity names the exact frozen `RecordGate`
passed to the policy.

This depends jointly on:

- Record creation requiring a Settings-authorized witness;
- Record omitting `store` and exposing no share/freeze function;
- exact gate ID and immutable Record `release_id` checks;
- Seal `ValidPtb` rejecting non-input arguments and non-approval commands; and
- key servers resolving current object inputs and evaluating with normal sender/owner
  validation.

The private `entry` modifier is defense in depth and Seal compatibility guidance. It
is not itself proof of current ownership.

## State and authority

- `RecordGate` is key-only. `init` creates one and freezes it immediately.
- No admin capability or mutable issuer list exists in this policy. Issuer governance
  belongs to `miso_record::settings::Settings`, the single creation boundary for the
  concrete Record type.
- Every ciphertext identity embeds the gate object ID, so another policy deployment
  cannot reinterpret it.
- The policy has no Pressing dependency. Any Record issuer authorized at creation is
  treated uniformly; a policy-local certificate allowlist would duplicate Settings
  and could drift from it.

## Identity validation

The identity is raw `[u8, u8, address, address, 32 bytes]`, exactly 98 bytes. Approval:

1. rejects fewer than 98 bytes before invoking the BCS reader;
2. peels schema, policy kind, gate address, release address, and a 32-byte nonce;
3. rejects any remainder, including a 99th trailing byte; and
4. checks schema `1`, release-mix kind `1`, exact gate ID, and exact Record release.

The public builder separately rejects non-32-byte nonces. Randomness remains an
encryptor obligation.

## Side effects and ownership

`seal_approve` takes `&RecordGate` and `&Record`, returns nothing, emits no event, and
performs no write. The tests snapshot both object IDs and the Record release across a
successful call.

The immutable borrow only proves possession when the verifier performs Seal's direct
input/current-owner checks. An unchecked simulation or a fabricated value outside
normal transaction input validation would not establish ownership.

## Adversarial verification

Ten Move tests cover init/freeze behavior, exact golden bytes, successful
side-effect-free approval, wrong gate/release, wrong schema/kind, short and trailing
identities, and invalid nonce length. Test Records are minted through an explicitly
authorized witness, not fabricated with a test-only constructor.

An external-package compiler probe separately attempts to instantiate `RecordGate`
and invoke private `seal_approve`; the compiler must reject both visibility breaches.

## Residual assumptions

- Compromise or misuse of Record's `SettingsAdminCap` can authorize an issuer whose
  Records this policy will accept. Revocation prevents future creation but does not
  invalidate Records already minted while authorized.
- Record or policy package upgrades could invalidate the reviewed assumptions.
- Seal threshold/key-server integrity and full-node freshness remain external trust
  assumptions.
- A holder can retain a key already fetched. Fresh nonces protect future identities;
  they do not revoke released key material.
