// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Seal policy for canonical Recording sessions held by Miso Record owners.
///
/// The package creates one frozen `RecordGate` at publication. Every Seal identity
/// pins that exact gate and one Recording. The caller supplies the immutable Release
/// named by their Record, and the policy proves that the Recording is a member of its
/// permanent tracklist. One encrypted session key can therefore remain canonical for
/// a Recording even when that Recording appears on multiple Releases.
///
/// Record now has `key + store`, so it may be shared or frozen. Move cannot inspect
/// an input object's ownership mode, and an immutable Record reference is therefore
/// no longer a sound proof of current address ownership. This revision keeps the
/// established identity parser but deliberately fails every approval closed until a
/// separate ownership/custody proof is designed.
module miso_record_seal_policy::policy;

use miso::release::Release;
use miso_record::record::{Self, Record};
use sui::bcs;

// === Identity constants ===

const SCHEMA_VERSION: u8 = 1;
const RECORDING_SESSION_POLICY_KIND: u8 = 1;
const IDENTITY_LENGTH: u64 = 98;
const NONCE_LENGTH: u64 = 32;

// === Errors ===

#[error]
const EInvalidIdentityLength: vector<u8> =
    b"Seal identity is shorter than the 98-byte Recording-session layout";

#[error]
const ETrailingIdentityBytes: vector<u8> =
    b"Seal identity has bytes after the 98-byte Recording-session layout";

#[error]
const EUnsupportedSchema: vector<u8> = b"Seal identity uses an unsupported schema version";

#[error]
const EWrongPolicyKind: vector<u8> = b"Seal identity is not a Recording-session policy";

#[error]
const EWrongGate: vector<u8> = b"Seal identity names a different Record gate";

#[error]
const EWrongRelease: vector<u8> = b"Record does not name the supplied Release";

#[error]
const ERecordingNotInRelease: vector<u8> =
    b"Recording is not a member of the Record's Release";

#[error]
const EInvalidNonceLength: vector<u8> = b"Seal identity nonce must be exactly 32 bytes";

#[error]
const EOwnershipUnprovable: vector<u8> =
    b"Record ownership is not provable after Record gained the store ability";

// === Objects ===

/// Immutable namespace for this Record policy deployment.
///
/// `RecordGate` is key-only and every production construction path freezes it before
/// storage. Its object ID is part of every identity, so ciphertexts cannot be
/// reinterpreted against another policy deployment.
public struct RecordGate has key {
    id: UID,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    transfer::freeze_object(new_gate(ctx))
}

fun new_gate(ctx: &mut TxContext): RecordGate {
    RecordGate { id: object::new(ctx) }
}

// === Identity ===

/// Build the canonical raw 98-byte Recording-session identity:
///
/// `[schema: u8 | kind: u8 | gate: address | recording: address | nonce: 32 raw bytes]`.
///
/// The returned bytes contain no inner BCS vector-length prefixes. Off-chain clients
/// reproduce this byte layout before passing it as Seal's required `vector<u8>` first
/// argument.
public fun recording_session_identity(
    gate_id: ID,
    recording_id: ID,
    nonce: vector<u8>,
): vector<u8> {
    assert!(nonce.length() == NONCE_LENGTH, EInvalidNonceLength);
    let mut id = vector[SCHEMA_VERSION, RECORDING_SESSION_POLICY_KIND];
    id.append(gate_id.to_bytes());
    id.append(recording_id.to_bytes());
    id.append(nonce);
    id
}

// === Seal policy ===

/// Validate the Recording-session request, then fail closed because `&Record` no
/// longer proves current ownership.
///
/// This function is side-effect-free: both objects are immutable borrows and it
/// returns nothing. The `id` argument must remain first for Seal's `ValidPtb` parser.
entry fun seal_approve(
    id: vector<u8>,
    gate: &RecordGate,
    record: &Record,
    release: &Release,
) {
    assert_identity_matches(id, gate, record, release);
    abort EOwnershipUnprovable
}

fun assert_identity_matches(
    id: vector<u8>,
    gate: &RecordGate,
    record: &Record,
    release: &Release,
) {
    assert!(id.length() >= IDENTITY_LENGTH, EInvalidIdentityLength);

    let mut reader = bcs::new(id);
    let schema = reader.peel_u8();
    let policy_kind = reader.peel_u8();
    let gate_id = reader.peel_address().to_id();
    let recording_id = reader.peel_address().to_id();
    let _nonce = reader.peel_u256();

    assert!(reader.into_remainder_bytes().is_empty(), ETrailingIdentityBytes);
    assert!(schema == SCHEMA_VERSION, EUnsupportedSchema);
    assert!(policy_kind == RECORDING_SESSION_POLICY_KIND, EWrongPolicyKind);
    assert!(gate_id == object::id(gate), EWrongGate);
    assert!(object::id(release) == record.release_id(), EWrongRelease);
    assert!(
        release.tracks().any!(|track| track.recording_id() == recording_id),
        ERecordingNotInRelease,
    );
}

// === Test helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun new_gate_for_testing(ctx: &mut TxContext): RecordGate {
    new_gate(ctx)
}

#[test_only]
public fun seal_approve_for_testing(
    id: vector<u8>,
    gate: &RecordGate,
    record: &Record,
    release: &Release,
) {
    seal_approve(id, gate, record, release)
}

#[test_only]
public fun validate_identity_for_testing(
    id: vector<u8>,
    gate: &RecordGate,
    record: &Record,
    release: &Release,
) {
    assert_identity_matches(id, gate, record, release)
}
