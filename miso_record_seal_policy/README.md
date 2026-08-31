# `miso_record_seal_policy`

A [Seal](https://docs.sui.io/sui-stack/seal/using-seal) policy for release-mix
material unlocked by ownership of a trusted Miso
`Record<Certificate>`.

```move
entry fun seal_approve<T: drop + store>(
    id: vector<u8>,
    gate: &CertificateGate,
    record: &Record<T>,
)
```

The package creates and freezes a `CertificateGate` for
`miso_pressing::certificate::Certificate` during `init`. It transfers a key-only
`PolicyAdminCap` to the publisher. The cap can later add another trusted certificate
type through the fixed `add_certificate_gate<T>` entry, which creates and immediately
freezes a new gate. No package upgrade is needed.

## Identity

The Seal inner identity is exactly 98 raw bytes:

| Offset | Length | Meaning |
|---:|---:|---|
| 0 | 1 | schema version: `1` |
| 1 | 1 | policy kind: `1` (`release mix`) |
| 2 | 32 | immutable `CertificateGate` object ID/address |
| 34 | 32 | release ID/address |
| 66 | 32 | random nonce |

There are no inner BCS length prefixes. The PTB still encodes the complete byte vector
normally as the first `vector<u8>` argument required by Seal. The on-chain
`release_mix_identity(gate_id, release_id, nonce)` helper is the canonical reference
builder and rejects any nonce not exactly 32 bytes.

Golden vector:

- gate: `0x11`
- release: `0x22`
- nonce: bytes `00` through `1f`
- identity:
  `010100000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000022000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`

Choose a fresh cryptographically random nonce once per encrypted key. The Move policy
can enforce its length, not its randomness. Reusing or predicting an identity lets a
holder fetch its Seal-derived key once and retain that key after transferring the
record.

## Security argument

Approval requires all of the following:

1. `Record<T>` is key-only, and the record core exposes address transfer and destroy
   but no share or freeze path. An outside package cannot use Sui's `public_*`
   ownership functions or wrap the record.
2. The identity names the exact frozen gate passed to the policy. The gate stores
   `type_name::with_original_ids<T>()`, which must match the record specialization.
3. The identity release must equal the record's immutable `release_id`.
4. Seal's `ValidPtb` accepts only direct `Input` arguments to `seal_approve*` calls;
   command results and gas are rejected. Key servers resolve object inputs to current
   on-chain versions and evaluate the policy as the session-key signer, so Sui's
   owner check requires that signer to own the address-owned record.

The private `entry` boundary follows Seal's compatibility guidance, but point 4—not
privacy alone—is what makes the immutable `&Record<T>` a current-ownership proof.
A verifier that skips transaction input checks does not establish ownership.

The approval function is side-effect-free: it takes only immutable object references,
fully parses and consumes the identity, and returns nothing. Gates are immutable, and
approval neither mutates nor self-transfers the record.

Adding a new gate does not widen an existing identity: every identity pins one gate
object ID. Compromise of the admin cap can authorize new gates and therefore new
identities, but cannot change the type or release checks for already encrypted data.
`transfer_admin_cap` is deliberately a one-step address transfer; operators must
verify the recipient byte-for-byte because a typo is irreversible and only disables
future gate creation (it does not affect the frozen launch gate).

## Deployment trust boundary

Authorization depends on the complete reviewed closure—not only this policy:

1. `miso_record`, whose key-only abilities and module-owned transfer surface make an
   immutable borrow a meaningful ownership proof;
2. `miso_pressing`, whose private `Certificate` construction defines which Records are
   authentic; and
3. `miso_record_seal_policy`, which binds that type, Record release, and frozen gate to
   a Seal identity.

The app and publishing CLI pin Miso's reviewed policy package, frozen gate, chain,
and committee configuration and reject descriptor-selected alternatives. Package
upgrade governance is an explicit organizational trust boundary: customers trust
Miso to operate the packages it deploys consistently with the reviewed behavior.
Sui does not offer Move code a general on-chain predicate proving another package
immutable, so clients do not attempt to manufacture one. A future design that needs
an on-chain proof would require a separately trusted off-chain attestor (for example,
a Nautilus enclave). There is no `Published.toml` in this source tree, and the policy
has not been published by this work.

## Build and test

```sh
sui move build
sui move test
```

The tests cover initialization, immutable gate creation, admin transfer, the golden
identity vector, success without mutation, certificate/gate/release mismatches,
schema and policy-kind mismatches, short identities, trailing bytes, and nonce length.

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
