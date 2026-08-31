// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Seal policy for release-mix material held by Miso Record owners.
///
/// The package creates one frozen `RecordGate` at publication. Every Seal identity
/// pins that exact gate and one release. The Record type itself is concrete and comes
/// from the pinned `miso_record` package; its shared Settings object governs which
/// module-controlled witness types can create Records.
///
/// Ownership is established by the combination of the key-only `Record`, this
/// package's exact gate/release checks, and Seal key servers' `ValidPtb` plus
/// current-owner simulation. The private `entry` boundary follows Seal guidance but
/// is not, by itself, the ownership proof.
module miso_record_seal_policy::policy;

use miso_record::record::{Self, Record};
use sui::bcs;

// === Identity constants ===

const SCHEMA_VERSION: u8 = 1;
const RELEASE_MIX_POLICY_KIND: u8 = 1;
const IDENTITY_LENGTH: u64 = 98;
const NONCE_LENGTH: u64 = 32;

// === Errors ===

#[error]
const EInvalidIdentityLength: vector<u8> =
    b"Seal identity is shorter than the 98-byte release-mix layout";

#[error]
const ETrailingIdentityBytes: vector<u8> =
    b"Seal identity has bytes after the 98-byte release-mix layout";

#[error]
const EUnsupportedSchema: vector<u8> = b"Seal identity uses an unsupported schema version";

#[error]
const EWrongPolicyKind: vector<u8> = b"Seal identity is not a release-mix policy";

#[error]
const EWrongGate: vector<u8> = b"Seal identity names a different Record gate";

#[error]
const EWrongRelease: vector<u8> = b"Record is a copy of a different release";

#[error]
const EInvalidNonceLength: vector<u8> = b"Seal identity nonce must be exactly 32 bytes";

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

/// Build the canonical raw 98-byte release-mix identity:
///
/// `[schema: u8 | kind: u8 | gate: address | release: address | nonce: 32 raw bytes]`.
///
/// The returned bytes contain no inner BCS vector-length prefixes. Off-chain clients
/// reproduce this byte layout before passing it as Seal's required `vector<u8>` first
/// argument.
public fun release_mix_identity(
    gate_id: ID,
    release_id: ID,
    nonce: vector<u8>,
): vector<u8> {
    assert!(nonce.length() == NONCE_LENGTH, EInvalidNonceLength);
    let mut id = vector[SCHEMA_VERSION, RELEASE_MIX_POLICY_KIND];
    id.append(gate_id.to_bytes());
    id.append(release_id.to_bytes());
    id.append(nonce);
    id
}

// === Seal policy ===

/// Approve release-mix key access for the current owner of a Miso Record.
///
/// This function is side-effect-free: both objects are immutable borrows and it
/// returns nothing. The `id` argument must remain first for Seal's `ValidPtb` parser.
entry fun seal_approve(
    id: vector<u8>,
    gate: &RecordGate,
    record: &Record,
) {
    assert_approved(id, gate, record)
}

fun assert_approved(
    id: vector<u8>,
    gate: &RecordGate,
    record: &Record,
) {
    assert!(id.length() >= IDENTITY_LENGTH, EInvalidIdentityLength);

    let mut reader = bcs::new(id);
    let schema = reader.peel_u8();
    let policy_kind = reader.peel_u8();
    let gate_id = reader.peel_address().to_id();
    let release_id = reader.peel_address().to_id();
    let _nonce = reader.peel_u256();

    assert!(reader.into_remainder_bytes().is_empty(), ETrailingIdentityBytes);
    assert!(schema == SCHEMA_VERSION, EUnsupportedSchema);
    assert!(policy_kind == RELEASE_MIX_POLICY_KIND, EWrongPolicyKind);
    assert!(gate_id == object::id(gate), EWrongGate);
    assert!(release_id == record.release_id(), EWrongRelease);
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
) {
    seal_approve(id, gate, record)
}
