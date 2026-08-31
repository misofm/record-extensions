# `miso_record_seal_policy`

A [Seal](https://docs.sui.io/sui-stack/seal/using-seal) policy for canonical
Recording sessions unlocked by ownership of a Miso `Record`.

```move
entry fun seal_approve(
    id: vector<u8>,
    gate: &RecordGate,
    record: &Record,
    release: &Release,
)
```

The package creates and freezes one key-only `RecordGate` during `init`. The
policy proves three relationships: the identity names that gate and a
Recording; the supplied Release is the immutable Release named by the Record;
and that Recording appears in the Release's immutable tracklist.

This Recording-bound identity is deliberate. One Recording may appear on
several Releases. A purchaser of any such Release should unlock the same
canonical Recording session without the session carrying or being rewritten
with one encrypted key envelope per Release.

## Identity

The Seal inner identity is exactly 98 raw bytes:

| Offset | Length | Meaning |
|---:|---:|---|
| 0 | 1 | schema version: `1` |
| 1 | 1 | policy kind: `1` (Recording session) |
| 2 | 32 | immutable `RecordGate` object ID/address |
| 34 | 32 | Recording ID/address |
| 66 | 32 | random session-generation nonce |

There are no inner BCS length prefixes. Choose a fresh cryptographically random
nonce and AES key whenever the canonical delivery generation is replaced.

## Security boundary

- The static Record type is the exact concrete format from the pinned package.
- Record Settings governs the witness types allowed to create Records.
- Record is key-only, so the PTB's owned input proves current ownership when
  Seal key servers resolve and dry-run the transaction as the session signer.
- The Release is shared but immutable in membership; its object ID must equal
  `record.release_id()` and its tracklist must contain the identity's Recording.
- The gate is frozen and its exact ID is part of the identity.

Previously fetched AES keys and plaintext cannot be revoked. Transferring a
Record prevents a fresh owner check from succeeding but cannot erase bytes the
former owner retained.

## Build and test

```sh
sui move build
sui move test
```
