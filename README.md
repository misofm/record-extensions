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

This repository currently has no packages.

### Retired: `record_seal_policy`

The Record Seal policy (`record_seal_policy`, three `seal_approve_*` entry functions
over `&Record`) was retired on 2026-09-14 and removed from this repository. It proved
membership, not ownership: `Record` has `store`, so a buyer can freeze or (at mint)
share it, after which any address could satisfy the policy and decrypt the whole
Release. See [misofm/audit#1](https://github.com/misofm/audit/issues/1).

Seal access will instead move to a future, separate key-only `Player` object that takes
custody of Records. That design does not exist yet. The testnet publication of the old
policy (`0x7e3759ef…343a2b54`) is immutable and orphaned; do not point key servers at
it, and do not publish it on mainnet.

## Design notes

- **Extensions, not forks.** Packages use Record's public API and do not modify the
  core object.
- **Ownership is not inferred from `&Record`.** Record has `store`, so a newly minted
  value can be shared or frozen. Either mode makes immutable access available without
  current address ownership, and Move cannot inspect the mode. Any future access policy
  must take custody of the Record rather than borrow it.

## Related

| Repo | Holds |
|------|-------|
| [`record`](https://github.com/misofm/record) | Record and its edition-local Pressing lifecycle |
| [`record-shop`](https://github.com/misofm/record-shop) | Primary-sale Listing and authorized distributor witness |
| [`musicos`](https://github.com/misofm/musicos) | `Composition`, `Recording`, `Release` |

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
