# `miso_record_seal_policy`

A fail-closed [Seal](https://seal-docs.wal.app/UsingSeal) policy shell for canonical
Recording sessions. It retains the established Recording-bound identity and validates
the Record-to-Release-to-Recording relationship, but does not release keys until
Record ownership has a sound proof compatible with `key + store`.

```move
entry fun seal_approve(
    id: vector<u8>,
    gate: &RecordGate,
    record: &Record,
    release: &Release,
)
```

The package creates and freezes one key-only `RecordGate` during `init`. The identity
names that gate and one Recording. The supplied Release must be the immutable Release
named by the Record, and that Recording must appear in its permanent tracklist.

## Identity

The Seal inner identity is exactly 98 raw bytes:

| Offset | Length | Meaning |
|---:|---:|---|
| 0 | 1 | schema version: `1` |
| 1 | 1 | policy kind: `1` (Recording session) |
| 2 | 32 | immutable `RecordGate` object ID/address |
| 34 | 32 | Recording ID/address |
| 66 | 32 | random session-generation nonce |

There are no inner BCS length prefixes. Choose a fresh cryptographically random nonce
and encryption key whenever the canonical delivery generation is replaced.

## Why approval is disabled

Record now has `key + store`. A buyer can use framework ownership functions to wrap,
freeze, or share a newly returned Record. Frozen and shared objects can be supplied by
non-owners as immutable references, and Move has no API that reveals the ownership
mode inside `seal_approve`. Seal evaluates the Move call with a full-node dry run; it
cannot strengthen a predicate the Move code does not express.

Consequently, `seal_approve` validates the complete identity, exact gate, exact
Record-to-Release relationship, and Recording membership, then aborts with
`EOwnershipUnprovable`. This prevents an apparently valid but bypassable policy from
reaching production. A future revision needs an explicit transfer-aware access
capability or a custody-specific proof.

Previously fetched keys and plaintext cannot be revoked. Disabling this package
revision only prevents new key releases through it.

## Build and test

```sh
sui move test --build-env testnet
sui move test --build-env mainnet
sui move test --build-env testnet --coverage
sui move coverage summary
```

Tests cover the Recording identity and membership rules, fail-closed matching
requests, a non-owner shared-Record bypass attempt, and the current end-to-end
Release → Pressing → authorized distributor → Record mint path. The production
policy module has literal 100% Move coverage.

The package pins Record `8a331e28…` and Protocol `6de5f988…`. Record pins that same
Protocol revision, so the Testnet and Mainnet lock graphs contain no duplicate
legacy Protocol or BPS sources.

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
