# `miso_record_acl`

> [Seal](https://seal-docs.wal.app) decryption policy for material gated on holding a Miso `Record`.

**Reads:** `Record` (miso-record core), plus `Release` / `Recording` / `Composition` (Miso protocol). Stores nothing, mutates nothing.

Gated material — a track's stems, a mixer session, a scan of the lyric sheet — is encrypted to a Seal identity in this package's namespace. When a listener asks to decrypt it, Seal key servers dry-run one of the `seal_approve_*` entries below with the requesting wallet as sender. Success **is** the authorization: the servers release the derived key, and nothing about the encrypted blob ever changes.

The same entries work for any verifier that can simulate a transaction — a session router deciding whether to hand out a mixer session, say. Seal is one consumer of the policy, not a dependency of it.

## Entry points

**The package is named for the credential; each entry is named for the subject.** The credential never varies — every approval starts from a `Record`, the only thing a listener holds. What varies is what is being opened. New subjects join as new entries, not new packages.

```move
entry fun seal_approve_release(id: vector<u8>, record: Record, release: &Release, ctx: &TxContext)
entry fun seal_approve_recording(id: vector<u8>, record: Record, release: &Release, ctx: &TxContext)
entry fun seal_approve_composition<RecordingShare, CompositionShare>(
    id: vector<u8>,
    record: Record,
    release: &Release,
    recording: &Recording<RecordingShare, CompositionShare>,
    composition: &Composition<CompositionShare>,
    ctx: &TxContext,
)
```

| Entry | Subject | Gates | Links |
|---|---|---|---|
| `seal_approve_release` | the release | liner notes, cover art pack, a whole-album session | 1–2 |
| `seal_approve_recording` | the recording | a track's stems, its mixer session | 1–3 |
| `seal_approve_composition` | the composition | material on the written work — lyrics, notation | 1–4 |

A recording may sit on several releases and a composition may be recorded many times, so a record for *any* release carrying a qualifying track approves the request — access is scoped to the subject, not to the release the listener happened to buy it on. `seal_approve_composition` therefore says the listener owns *a* recording of the written work, not every recording of it; where that is too broad, gate with `seal_approve_recording`.

## Identity

Every identity in this namespace is the subject's 32 bytes followed by a BCS-encoded nonce:

```
id = subject ‖ bcs(nonce: vector<u8>)
```

The **subject** is the thing being opened — a release, a recording, or a composition. Never the record: a record is the credential, and binding keys to it would make material unreadable the moment the copy changed hands.

Each entry pins the subject. Where it already arrives as an object (`seal_approve_release`, `seal_approve_composition`) the identity is checked against it; where it does not — a recording is named only by id — the subject is read *out* of the identity and handed to the tracklist check. Without that pinning the policy would fail open: a listener holding one legitimate record could present it and collect the key for anything in the namespace.

Build and read identities through the module rather than restating the layout:

```move
public fun identity(subject: ID, nonce: vector<u8>): vector<u8>
public fun subject_of(id: vector<u8>): ID   // inverse; aborts on a malformed identity
```

> **Choose the nonce at random, once per encryption.** A key server derives one fixed key per identity, and that key opens everything ever encrypted to it — including material that does not exist yet. A listener who holds a qualifying record can fetch the key for any identity they can *predict*, and keep it after selling the record. A random nonce makes future identities unguessable; a counter, a timestamp, or an empty nonce does not. See Seal's [Fetched keys can be used for future decryptions](https://seal-docs.wal.app/SecurityBestPractices#fetched-keys-can-be-used-for-future-decryptions).

## The chain of links

Every approval is a chain, and Sui enforces the first link itself:

1. **wallet → record.** The `Record` is taken **by value** and handed back to the sender, so the fullnode's input checker has already verified the sender owns it. By-value is the whole security argument — `&Record` would be a hole, because `Record` has `store` and a shared object is a legal `&` input for *any* sender, so one buyer calling `public_share_object` would open the release to everyone. By value rejects shared inputs (they cannot be transferred out) and immutable ones (they cannot be passed by value).
2. **record → release.** `record.release_id() == release.id()`. `seal_approve_release` stops here.
3. **release → recording.** `release.contains_recording(subject_of(id))`. `seal_approve_recording` stops here.
4. **recording → composition.** Not a runtime assert — a recording carries its composition as the `CompositionShare` *phantom type*, never a stored id, so `Recording<_, C>` and `Composition<C>` only type-check together. The 1:1 share-type↔object invariant (`share::initialize` consumes the `TreasuryCap`) is what makes that a proof. The `composition` argument is read by no line of the function — it is there so the caller names the composition it gates **by object id**, rather than lifting the type argument off the recording, which would make the check vacuously true and fail open in silence.

The link checks are exposed as `assert_grants_release` / `assert_grants_recording` / `assert_grants_composition`, so a later custody shape — a player's record shelf, a second policy — reuses them rather than restating the rule.

## Simulating the policy

A Seal key server preserves link 1: it simulates through gRPC `SimulateTransaction` with `checks` unset, which defaults to enabled, and strips only each input's version and digest so the fullnode resolves against current state. Owner checks run.

> **Any other verifier must keep those checks on** — `dryRun`, or `SimulateTransaction` with `checks` unset. `devInspect` defaults to `skipChecks: true`, which skips the owner check entirely and would let any sender name any record. Link 1 is the one link this package does not implement, so losing it is silent.

Because a simulation reports only success or failure, the module leaves nothing to inference: it aborts with `#[error]` constants, so the failure carries a readable reason a verifier can log. Those abort codes embed the source line, so off-chain code must treat them as diagnostics and branch only on success/failure.

Seal asks that a policy be free of side effects. Executed for real, every entry is a self-transfer no-op — and a key server reads only the simulation's status — so they are harmless to leave callable on chain.

## Usage

Encrypting a track's stems to the recording that owns them:

```ts
import { bcs } from '@mysten/bcs';
import { fromHex, toHex } from '@mysten/sui/utils';

const nonce = crypto.getRandomValues(new Uint8Array(16));
const id = toHex(new Uint8Array([
  ...fromHex(recordingId),
  ...bcs.vector(bcs.u8()).serialize(nonce).toBytes(),
]));

const { encryptedObject } = await sealClient.encrypt({
  threshold: 2,
  packageId: MISO_RECORD_ACL_PACKAGE_ID,
  id,
  data: stems,
});
```

Decrypting it, as a listener who owns a record for a release the track sits on:

```ts
const tx = new Transaction();
tx.moveCall({
  target: `${MISO_RECORD_ACL_PACKAGE_ID}::acl::seal_approve_recording`,
  arguments: [
    tx.pure.vector('u8', fromHex(id)),
    tx.object(recordId),    // owned by the sender — the fullnode checks this
    tx.object(releaseId),   // shared; must carry a track for `recordingId`
  ],
});

const stems = await sealClient.decrypt({
  data: encryptedObject,
  sessionKey,
  txBytes: await tx.build({ client: suiClient, onlyTransactionKind: true }),
});
```

`seal_approve_composition` additionally takes the `Recording` and `Composition` objects, and its type arguments are the recording's own — `Recording<MASTER, SONG>` with `Composition<SONG>`. Never lift `SONG` off the recording's type when the composition being gated is what you are trying to name.

For large payloads, encrypt the stems with your own symmetric key and seal only that key: rotating key servers or re-scoping access then costs one small re-encryption rather than re-uploading the blob. See Seal's [layered encryption](https://seal-docs.wal.app/SecurityBestPractices#use-layered-encryption-for-critical-or-large-data).

## Errors

| Constant | Meaning |
|---|---|
| `EWrongRelease` | The record is not a copy of the release presented — link 2 |
| `ERecordingNotOnRelease` | The release has no track for the recording — link 3 |
| `EMalformedIdentity` | The identity is not exactly `[subject ‖ nonce]` |
| `EWrongSubject` | The identity names a different subject than the one presented |

## Build & test

```sh
sui move build
sui move test
```

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) © Miso Labs, Inc.
