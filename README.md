# Miso Record Extensions

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](#license)
[![Move](https://img.shields.io/badge/Move-2024-black.svg)](https://docs.sui.io/concepts/sui-move-concepts)

> First-party extension packages for the [Miso Record](https://github.com/misofm/record)
> on [Sui](https://sui.io).

The Record is Miso's concrete, witness-authorized distribution object:

```move
public struct Record has key, store {
    id: UID,
    release_id: ID,
    registry_id: ID,
    number: u64,
    created_at_ms: u64,
    purchase_currency: TypeName,
    purchased_by: address,
}
```

Additional extension state can still be attached under module-controlled dynamic-field
keys.

## Packages

| Package | Reads | Summary |
|---------|-------|---------|
| [`miso_record_seal_policy`](./miso_record_seal_policy) | `Record` | Frozen-gate identity parser, currently fail-closed because `&Record` cannot prove ownership. |

## Dependencies

Each package is independently publishable and pins reviewed source revisions:

```toml
miso_record = { git = "https://github.com/misofm/record.git", rev = "c3f5310e0f52b1aa5553636c7f8edae7d01d0010" }
```

The Seal policy no longer depends on Pressing. Record's exact package type is the
format boundary, and `miso_record::Settings` decides which witness types can create
instances of it.

## Design notes

- **Extensions, not forks.** Packages use Record's public API and do not modify the
  core object.
- **Ownership is not inferred from `&Record`.** Record has `store`, so a newly minted
  value can be shared or frozen. Either mode makes immutable access available without
  current address ownership, and Move cannot inspect the mode. The policy therefore
  fails closed pending an explicit access-capability or custody design.
- **One policy gate.** `miso_record_seal_policy` freezes a single `RecordGate` during
  publication. The gate ID and Recording ID remain embedded in the established
  98-byte identity layout; the supplied Release must bind them to the Record.

## Build and test

```sh
cd miso_record_seal_policy
sui move build
sui move test
```

## Related

| Repo | Holds |
|------|-------|
| [`miso-record`](https://github.com/misofm/record) | Concrete Record and witness Settings |
| [`miso-pressing`](https://github.com/misofm/pressing) | First-party sale path and authorized mint witness |
| [`miso-protocol`](https://github.com/misonetwork/miso-protocol) | `Composition`, `Recording`, `Release` |

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
