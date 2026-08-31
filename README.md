# Miso Record Extensions

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](#license)
[![Move](https://img.shields.io/badge/Move-2024-black.svg)](https://docs.sui.io/concepts/sui-move-concepts)

> A monorepo of first-party extension packages for the [Miso record](https://github.com/misofm/record) on [Sui](https://sui.io), maintained by Miso.

The `Record` — an owned, transferable copy of a release — is deliberately slim:

```move
public struct Record<Certificate: drop + store> has key {
    id: UID,
    release_id: ID,
    certificate: Certificate,
}
```

Only what is fixed at birth, true forever, and meaningful without a namespace. Everything else is an **extension**: a standalone Move package that either attaches its own state to the record's `UID` as a dynamic field, or reads the record to decide something. Serial numbers, sale terms, playtime, vouchers, decryption rights — none of it lives in the struct, and none of it requires re-publishing the core.

Each package here is independent and published separately — depend on only the ones you need. **For how a given extension works, see its own `README.md`** (linked below); this page stays at the monorepo level.

## Packages

| Package | Reads | Summary |
|---------|-------|---------|
| [`miso_record_seal_policy`](./miso_record_seal_policy) | `Record<Certificate>`, pressing `Certificate` | Immutable-gate Seal policy for release-mix keys, with exact certificate type, gate, and release binding. |

## Dependencies

| Dependency | Used by | Role |
|------------|---------|------|
| [`miso_record`](https://github.com/misofm/record) | all | The generic `Record<Certificate>` itself |
| [`miso_pressing`](https://github.com/misofm/pressing) | `miso_record_seal_policy` | The initially trusted pressing certificate type |

The Seal policy pins the reviewed key-only Record and Pressing source revisions. New
on-chain package IDs will be recorded separately when the stack is freshly published:

```toml
# miso_record_seal_policy
miso_record = { git = "https://github.com/misofm/record.git", subdir = "move", rev = "46dadad176ceadef8f698498968a1688af96960b" }
miso_pressing = { git = "https://github.com/misofm/pressing.git", rev = "dc44fa7c61ecdd92e4c672057b4c6142e874053e" }
```

## Build & test

From the package directory:

```sh
sui move build
sui move test
```

## Design notes

- **Extensions, not forks.** These packages operate on the record through its public API and its raw `&mut UID`; they never modify the core, so access, sale, and metadata models evolve independently of the object they hang off.
- **Possession is the authority.** Only a record's owner can produce a `&mut Record`, so `miso_record::record::uid_mut` is fully open — no capability, no allowlist. An extension that wants to be *unforgeable* rather than merely owner-written keys off the record's derivation from its minting parent instead.
- **Key-only ownership makes immutable borrows safe under checked simulation.** The record core owns every transfer path and exposes no share or freeze function. `miso_record_seal_policy` combines that invariant with Seal's direct-input/current-owner validation and exact gate, original certificate type, and release checks.

## Related

| Repo | Holds |
|------|-------|
| [`miso-record`](https://github.com/misofm/record) | The generic `Record<Certificate>` core |
| [`miso-pressing`](https://github.com/misofm/pressing) | The trusted pressing certificate and V1 sale path |
| [`miso-protocol`](https://github.com/misonetwork/miso-protocol) | `Composition`, `Recording`, `Release` |
| [`miso-protocol-extensions`](https://github.com/misonetwork/miso-protocol-extensions) | Extensions to those protocol objects |

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
