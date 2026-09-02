# Miso Record Extensions

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](#license)
[![Move](https://img.shields.io/badge/Move-2024-black.svg)](https://docs.sui.io/concepts/sui-move-concepts)

> First-party extension packages for the [Miso Record](https://github.com/misofm/record)
> on [Sui](https://sui.io).

The Record is Miso's concrete, Pressing-issued purchase object:

```move
public struct Record has key, store {
    id: UID,
    release_id: ID,
    pressing_id: ID,
    edition: u16,
    number: u32,
    purchase_currency: TypeName,
    purchase_price: u64,
    purchased_by: address,
    purchased_timestamp_ms: u64,
}
```

Additional extension state can still be attached under module-controlled dynamic-field
keys.

## Packages

| Package | Reads | Summary |
|---------|-------|---------|
| [`record_seal_policy`](./record_seal_policy) | `Record` | Frozen-gate identity parser, currently fail-closed because `&Record` cannot prove ownership. |

## Dependencies

Each package is independently publishable and pins reviewed source revisions:

```toml
miso_record = { git = "https://github.com/misofm/record.git", rev = "8a331e2880723aa0330dee00c55525aa6b4c1516" }
miso = { git = "https://github.com/misonetwork/protocol.git", rev = "6de5f9881ee62c81c57ce16832efc24dc33ae429" }
```

Record's exact package type is the format boundary. Its Pressing authorizes the
distributor witness types that may create Records and owns edition-local issuance.
The Seal policy reads only the resulting Record and immutable Release. Record and
the policy pin the same Protocol revision, so both network lock graphs resolve one
Protocol package and one immutable BPS dependency.

## Design notes

- **Extensions, not forks.** Packages use Record's public API and do not modify the
  core object.
- **Ownership is not inferred from `&Record`.** Record has `store`, so a newly minted
  value can be shared or frozen. Either mode makes immutable access available without
  current address ownership, and Move cannot inspect the mode. The policy therefore
  fails closed pending an explicit access-capability or custody design.
- **One policy gate.** `record_seal_policy` freezes a single `RecordGate` during
  publication. The gate ID and Recording ID remain embedded in the established
  98-byte identity layout; the supplied Release must bind them to the Record.

## Build and test

```sh
cd record_seal_policy
sui move test --build-env testnet
sui move test --build-env mainnet
sui move test --build-env testnet --coverage
sui move coverage summary
```

## Related

| Repo | Holds |
|------|-------|
| [`record`](https://github.com/misofm/record) | Record and its edition-local Pressing lifecycle |
| [`record-shop`](https://github.com/misofm/record-shop) | Primary-sale Listing and authorized distributor witness |
| [`protocol`](https://github.com/misonetwork/protocol) | `Composition`, `Recording`, `Release` |

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
