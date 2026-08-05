# Miso Record Extensions

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](#license)
[![Move](https://img.shields.io/badge/Move-2024-black.svg)](https://docs.sui.io/concepts/sui-move-concepts)

> A monorepo of first-party extension packages for the [Miso record](https://github.com/misonetwork/miso-record) on [Sui](https://sui.io), maintained by Miso.

The `Record` — an owned, transferable copy of a release — is deliberately slim:

```move
public struct Record has key, store {
    id: UID,
    release_id: ID,
    created_at_ms: u64,
}
```

Only what is fixed at birth, true forever, and meaningful without a namespace. Everything else is an **extension**: a standalone Move package that either attaches its own state to the record's `UID` as a dynamic field, or reads the record to decide something. Serial numbers, sale terms, playtime, vouchers, decryption rights — none of it lives in the struct, and none of it requires re-publishing the core.

Each package here is independent and published separately — depend on only the ones you need. **For how a given extension works, see its own `README.md`** (linked below); this page stays at the monorepo level.

## Packages

| Package | Reads | Summary |
|---------|-------|---------|
| [`miso_record_acl`](./miso_record_acl) | `Record`, `Release`, `Recording`, `Composition` | [Seal](https://seal-docs.wal.app) decryption policy: releases the key for release-, recording-, or composition-scoped material to a wallet holding a qualifying record. |

## Dependencies

| Dependency | Used by | Role |
|------------|---------|------|
| [`miso_record`](https://github.com/misonetwork/miso-record) | all | The `Record` itself |
| [`miso`](https://github.com/misonetwork/miso-protocol) | `miso_record_acl` | Core `Composition` / `Recording` / `Release` / `Track` types |

Both resolve to sibling checkouts (`../../miso-record/move`, `../../miso-protocol/move`). To build against the published packages instead, point them at their git sources:

```toml
miso_record = { git = "https://github.com/misonetwork/miso-record.git", subdir = "move", rev = "main" }
miso = { git = "https://github.com/misonetwork/miso-protocol.git", subdir = "move", rev = "main" }
```

## Build & test

Every directory is a standalone Move package. From any package directory:

```sh
sui move build
sui move test
```

## Design notes

- **Extensions, not forks.** These packages operate on the record through its public API and its raw `&mut UID`; they never modify the core, so access, sale, and metadata models evolve independently of the object they hang off.
- **Possession is the authority.** Only a record's owner can produce a `&mut Record`, so `miso_record::record::uid_mut` is fully open — no capability, no allowlist. An extension that wants to be *unforgeable* rather than merely owner-written keys off the record's derivation from its minting parent instead.
- **A record is a credential, not a subject.** `miso_record_acl` gates material by asking what the record grants access to — a release, a track's stems, a written work — never by naming the record itself. See its README for why the record is taken by value.

## Related

| Repo | Holds |
|------|-------|
| [`miso-record`](https://github.com/misonetwork/miso-record) | The `Record` core and the `Settings` mint allowlist |
| [`miso-pressing`](https://github.com/misonetwork/miso-pressing) | The V1 sale — serials, purchase receipts, sale terms |
| [`miso-protocol`](https://github.com/misonetwork/miso-protocol) | `Composition`, `Recording`, `Release` |
| [`miso-protocol-extensions`](https://github.com/misonetwork/miso-protocol-extensions) | Extensions to those protocol objects |

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
