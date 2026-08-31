# `miso_record_seal_policy`

A [Seal](https://docs.sui.io/sui-stack/seal/using-seal) policy for release-mix
material unlocked by ownership of a Miso `Record`.

```move
entry fun seal_approve(
    id: vector<u8>,
    gate: &RecordGate,
    record: &Record,
)
```

The package creates and freezes one key-only `RecordGate` during `init`. There is no
policy admin capability or issuer-type registry: the pinned concrete Record type is
the format boundary, while `miso_record::settings::Settings` governs the witness types
that may create Records.

## Identity

The Seal inner identity remains exactly 98 raw bytes:

| Offset | Length | Meaning |
|---:|---:|---|
| 0 | 1 | schema version: `1` |
| 1 | 1 | policy kind: `1` (`release mix`) |
| 2 | 32 | immutable `RecordGate` object ID/address |
| 34 | 32 | release ID/address |
| 66 | 32 | random nonce |

There are no inner BCS length prefixes. The PTB encodes the complete byte vector
normally as Seal's first `vector<u8>` argument. The on-chain
`release_mix_identity(gate_id, release_id, nonce)` helper is the canonical builder and
rejects nonces that are not exactly 32 bytes.

Golden vector for gate `0x11`, release `0x22`, and nonce bytes `00` through `1f`:

`010100000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000022000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`

Choose a fresh cryptographically random nonce per encrypted key. Move can enforce
length, not randomness. A holder can retain a key already fetched after transferring
the Record; nonce freshness prevents predicting identities for future material, not
revocation of previously released keys.

## Security argument

Approval requires all of the following:

1. The static argument type is the exact `Record` from the dependency pinned by this
   policy package. Record creation itself consumes a witness authorized by shared
   Record Settings.
2. Record is key-only; its defining module exposes address transfer and destruction
   but no share/freeze path. Outside packages cannot use framework `public_*`
   ownership functions or wrap it.
3. The identity names the exact frozen `RecordGate` supplied to the policy.
4. The identity's release equals the Record's immutable `release_id`.
5. Seal `ValidPtb` accepts only direct input arguments to `seal_approve*`; key servers
   resolve those inputs to current versions and evaluate as the session-key signer,
   invoking Sui's normal owner check.

The private `entry` boundary follows Seal compatibility guidance, but item 5—not
privacy alone—is what turns `&Record` into a current-ownership proof. A verifier that
skips transaction-input checks does not establish ownership.

The approval function is side-effect-free. It takes immutable references, fully
parses and consumes the identity, emits nothing, and returns nothing.

## Deployment trust boundary

Authorization depends on this reviewed closure:

1. `miso_record`, whose Settings enforces witness authorization and whose key-only
   abilities make immutable Record input meaningful; and
2. `miso_record_seal_policy`, which binds that Record to an exact frozen gate and
   release.

Pressing is one authorized issuer but is not part of the policy's static dependency
or its approval predicate. Record Settings administration is an explicit governance
boundary: an incorrectly authorized witness could create Records that this policy
would accept.

Applications pin the reviewed policy package, `RecordGate`, chain, and committee.
Package upgrade governance remains an operator/customer trust assumption because
Move cannot generally prove that another package's `UpgradeCap` no longer exists.

## Build and test

```sh
sui move build
sui move test
```

Tests cover gate freezing, the golden identity vector, side-effect-free success,
wrong gate/release, wrong schema/kind, short and trailing identities, and nonce
length. Compiler probes additionally verify that outside packages cannot construct a
`RecordGate` or call the private approval function from Move.

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
