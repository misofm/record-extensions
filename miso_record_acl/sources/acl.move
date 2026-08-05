// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Seal decryption policy for material gated on holding a `Record`.
///
/// One question, answered by simulation: *may this sender open this?* A Seal key
/// server dry-runs one of the `seal_approve_*` entries with the requesting wallet
/// as sender, and success **is** the authorization — the server then releases the
/// derived key for the identity that was asked for.
///
/// **The package is named for the credential; each entry is named for the
/// subject.** The credential never varies — every approval here starts from a
/// `Record`, the only thing a listener holds. What varies is what is being
/// opened:
///
/// | Entry | Gates | Links |
/// |---|---|---|
/// | `seal_approve_release` | liner notes, cover art pack, a whole-album session | 1–2 |
/// | `seal_approve_recording` | a track's stems, its mixer session | 1–3 |
/// | `seal_approve_composition` | material on the written work — lyrics, notation | 1–4 |
///
/// New subjects join as new entries, not as new packages.
///
/// # Identity
///
/// Every entry takes Seal's identity as its first argument, and every identity in
/// this package's namespace is `[subject ‖ nonce]` — see `identity`. **The subject
/// is the thing being opened, never the record**, and each entry pins it: where
/// the subject already arrives as an object it is checked against the identity,
/// and where it does not (a recording is named only by id) it is read *out* of the
/// identity. Without that pinning the policy fails open — a listener holding a
/// record for one release could present it and collect the key for anything in the
/// namespace.
///
/// # The chain of links
///
/// Every approval is a chain, and Sui enforces the first link itself:
///
/// 1. **wallet → record.** The `Record` is taken BY VALUE and handed straight
///    back to the sender. By-value is the entire security argument, and
///    `&Record` would be a hole: `Record` has `store`, so anyone may
///    `public_share_object` one, and a shared object is a legal `&` input for
///    *any* sender — one buyer sharing their copy would open the release to
///    everyone. Taken by value it rejects shared inputs (a shared object cannot
///    be transferred out) and immutable ones (an immutable object cannot be
///    passed by value), which leaves exactly one case — the sender owns it,
///    which the fullnode's input checker verified before execution began.
/// 2. **record → release.** The record is a copy of the release presented.
///    `seal_approve_release` stops here.
/// 3. **release → recording.** That release has a track for the recording.
///    `seal_approve_recording` stops here.
/// 4. **recording → composition.** The recording is a recording *of* that
///    composition. Unlike links 2 and 3 this one is **not a runtime assert**: a
///    recording carries its composition as the `CompositionShare` phantom type,
///    never as a stored id (`miso::recording`, module doc), so the link is
///    discharged by the type checker — see `assert_grants_composition`.
///
/// # Simulating this policy
///
/// A Seal key server preserves link 1: it simulates through gRPC
/// `SimulateTransaction` with `checks` unset, which defaults to enabled, and
/// strips only each input's version and digest so the fullnode resolves against
/// current state. Owner checks run, so the record must really be the sender's.
///
/// **Any other verifier must keep those checks on** — `dryRun`, or
/// `SimulateTransaction` with `checks` unset. `devInspect` defaults to
/// `skipChecks: true`, which skips the owner check entirely and would let any
/// sender name any record. Link 1 is the one link this module does not implement,
/// so losing it is silent.
///
/// Because a simulation reports only success or failure, this module leaves
/// nothing to inference: it aborts with `#[error]` constants, so the failure
/// carries a readable reason a verifier can log. Note that `#[error]` abort codes
/// embed the source line, so off-chain code must treat them as diagnostics and
/// branch only on success/failure.
///
/// Seal asks that a policy be free of side effects. Executed for real, every entry
/// here is a self-transfer no-op — and a key server reads only the simulation's
/// status — so they are harmless to leave callable on chain.
///
/// A recording may appear on more than one release (a single and an album), and
/// a composition may be recorded many times. A record for *any* release carrying
/// a qualifying track grants access — access is scoped to the subject, not to the
/// release the listener happened to buy it on.
module miso_record_acl::acl;

use miso::composition::Composition;
use miso::recording::Recording;
use miso::release::Release;
use miso_record::record::Record;
use sui::bcs;

// === Errors ===

#[error]
const EWrongRelease: vector<u8> = b"Record is not a copy of this release";

#[error]
const ERecordingNotOnRelease: vector<u8> = b"Release has no track for this recording";

#[error]
const EMalformedIdentity: vector<u8> = b"Identity is not [subject id][nonce]";

#[error]
const EWrongSubject: vector<u8> = b"Identity names a different subject than the one presented";

// === Identity ===

/// The Seal identity for `subject` under `nonce`: the subject's 32 bytes followed
/// by the BCS-encoded nonce. Encrypt to this, and gate it with the entry named for
/// the subject's kind.
///
/// **Choose the nonce at random, once per encryption.** A key server derives one
/// fixed key per identity, and that key opens everything ever encrypted to it —
/// including material that does not exist yet. A listener who holds a qualifying
/// record can therefore fetch the key for any identity they can *predict*, and
/// keep it after selling the record. A random nonce makes future identities
/// unguessable; a counter, a timestamp, or an empty nonce does not.
public fun identity(subject: ID, nonce: vector<u8>): vector<u8> {
    let mut id = subject.to_bytes();
    id.append(bcs::to_bytes(&nonce));
    id
}

/// The subject an identity names — the inverse of `identity`. Aborts unless `id`
/// is exactly `[subject ‖ nonce]`, so a policy can neither be handed a truncated
/// identity nor one carrying trailing bytes that a key server would treat as a
/// different key.
public fun subject_of(id: vector<u8>): ID {
    let mut reader = bcs::new(id);
    let subject = reader.peel_address().to_id();
    let _nonce = reader.peel_vec_u8();
    assert!(reader.into_remainder_bytes().is_empty(), EMalformedIdentity);
    subject
}

// === Public Functions ===

/// Assert that `record` is a copy of `release` — link 2 on its own. Composable
/// by any package that has already established who holds the record: a later
/// player shelf, a second Seal policy.
public fun assert_grants_release(record: &Record, release: &Release) {
    assert!(record.release_id() == release.id(), EWrongRelease);
}

/// Assert that `record` grants access to `recording_id` — links 2 and 3: the
/// record is a copy of `release`, and `release` carries a track for that
/// recording.
public fun assert_grants_recording(record: &Record, release: &Release, recording_id: ID) {
    assert_grants_release(record, release);
    assert!(release.contains_recording(recording_id), ERecordingNotOnRelease);
}

/// Assert that `record` grants access to the composition `recording` is a
/// recording *of* — links 2, 3 and 4.
///
/// **Link 4 is discharged by the type checker, not by a line of this function.**
/// `Recording<_, CompositionShare>` and `Composition<CompositionShare>` can only
/// be passed together when they share the composition's share type, and
/// `miso_share::share::initialize` asserts zero supply and consumes the
/// currency's `TreasuryCap`, so a share type belongs to exactly one object. That
/// 1:1 invariant is what makes the shared phantom a proof rather than a hint.
///
/// `composition` is therefore read by no statement here — its *type* is the
/// assertion. It is a parameter anyway so that the caller names the composition
/// it is gating **by object id**. Passing only the type argument would work
/// identically, and would invite a caller to lift `CompositionShare` off the
/// recording's own type — which makes the check vacuously true and fails open in
/// silence.
public fun assert_grants_composition<RecordingShare, CompositionShare>(
    record: &Record,
    release: &Release,
    recording: &Recording<RecordingShare, CompositionShare>,
    _composition: &Composition<CompositionShare>,
) {
    assert_grants_recording(record, release, recording.id());
}

// === Seal Policy ===

/// Approve a key request for release-scoped material: the sender holds a copy of
/// `release`. Identity: `[release id ‖ nonce]`.
///
/// Private `entry` on purpose — what Seal recommends for upgrade compatibility,
/// and what keeps link 1 honest: a PTB cannot pass an entry function the *result*
/// of a public call, so no one can conjure a `Record` mid-transaction and feed it
/// in. It must be a direct owned-object input. The same applies to the two entries
/// below.
entry fun seal_approve_release(
    id: vector<u8>,
    record: Record,
    release: &Release,
    ctx: &TxContext,
) {
    assert!(subject_of(id) == release.id(), EWrongSubject);
    assert_grants_release(&record, release);
    transfer::public_transfer(record, ctx.sender())
}

/// Approve a key request for recording-scoped material: the sender holds a record
/// for a release carrying a track for the recording. Identity:
/// `[recording id ‖ nonce]`.
///
/// The recording is named by the identity alone — there is nothing to check it
/// against, and nothing gained by also passing the `Recording` object.
entry fun seal_approve_recording(
    id: vector<u8>,
    record: Record,
    release: &Release,
    ctx: &TxContext,
) {
    assert_grants_recording(&record, release, subject_of(id));
    transfer::public_transfer(record, ctx.sender())
}

/// Approve a key request for composition-scoped material: the sender holds a
/// record reaching `composition`, through a recording of it that sits on
/// `release`. Identity: `[composition id ‖ nonce]`.
///
/// Note what this approves and what it does not: the listener owns *a* recording
/// of the written work, not every recording of it. If composition-scoped material
/// should only open to a particular recording's owners, gate it with
/// `seal_approve_recording` instead.
entry fun seal_approve_composition<RecordingShare, CompositionShare>(
    id: vector<u8>,
    record: Record,
    release: &Release,
    recording: &Recording<RecordingShare, CompositionShare>,
    composition: &Composition<CompositionShare>,
    ctx: &TxContext,
) {
    assert!(subject_of(id) == composition.id(), EWrongSubject);
    assert_grants_composition(&record, release, recording, composition);
    transfer::public_transfer(record, ctx.sender())
}

// === Test Only ===

/// The `seal_approve_*` entries are private (uncallable from other modules), so
/// tests go through these wrappers.
#[test_only]
public fun seal_approve_release_for_testing(
    id: vector<u8>,
    record: Record,
    release: &Release,
    ctx: &TxContext,
) {
    seal_approve_release(id, record, release, ctx)
}

#[test_only]
public fun seal_approve_recording_for_testing(
    id: vector<u8>,
    record: Record,
    release: &Release,
    ctx: &TxContext,
) {
    seal_approve_recording(id, record, release, ctx)
}

#[test_only]
public fun seal_approve_composition_for_testing<RecordingShare, CompositionShare>(
    id: vector<u8>,
    record: Record,
    release: &Release,
    recording: &Recording<RecordingShare, CompositionShare>,
    composition: &Composition<CompositionShare>,
    ctx: &TxContext,
) {
    seal_approve_composition(id, record, release, recording, composition, ctx)
}
