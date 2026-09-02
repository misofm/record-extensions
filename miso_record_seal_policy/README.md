# `miso_record_seal_policy`

A [Seal](https://docs.sui.io/sui-stack/seal/using-seal) policy package that
gates Composition, Recording, and Release data with a Miso Record.

```move
entry fun seal_approve_composition<CompositionShare>(
    id: vector<u8>,
    record: &Record,
    release: &Release,
    composition: &Composition<CompositionShare>,
)

entry fun seal_approve_recording<RecordingShare, CompositionShare>(
    id: vector<u8>,
    record: &Record,
    release: &Release,
    recording: &Recording<RecordingShare, CompositionShare>,
)

entry fun seal_approve_release(
    id: vector<u8>,
    record: &Record,
    release: &Release,
)
```

Every function verifies that `record.release_id()` names the supplied Release.
Composition and Recording policies also select a track and verify both the
track member ID and the supplied object's ID.

## Identities

The inner Seal identities use raw fixed-width fields without inner BCS vector
length prefixes:

| Policy | Layout | Length |
|---|---|---:|
| Composition | `release_id (32) \| track_idx (1) \| composition_id (32)` | 65 bytes |
| Recording | `release_id (32) \| track_idx (1) \| recording_id (32)` | 65 bytes |
| Release | `release_id (32)` | 32 bytes |

Clients and SDKs construct these inner identities offchain according to the
layouts above.

## Record-reference semantics

The policy deliberately treats the ability to supply a usable `&Record` as the
entitlement. Address-owned Records can only be supplied by their owner. If a
Record is shared or frozen, other callers can supply its reference and satisfy
this policy.

## Build and test

```sh
sui move test --build-env testnet
sui move test --build-env mainnet
```

Tests cover all three successful approval paths, invalid track indices,
malformed identity lengths, and multi-transaction scenarios in which a Record
owner supplies the wrong shared Composition, Recording, or Release.

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
