// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Seal policy for release-mix material held by trusted record owners.
///
/// A `CertificateGate` is an immutable, key-only authorization object for exactly one
/// certificate type. The package creates the pressing-certificate gate at publication;
/// the `PolicyAdminCap` can create and freeze more gates later without upgrading the
/// package. Every Seal identity pins a particular gate, so adding a gate cannot widen
/// access to identities encrypted against an earlier one.
///
/// Ownership is established by the combination of a key-only `Record`, this package's
/// exact gate/type/release checks, and Seal key servers' `ValidPtb` + current-owner
/// simulation. The private `entry` boundary is recommended by Seal, but is not by
/// itself the ownership proof.
module miso_record_seal_policy::policy;

use miso_pressing::certificate::Certificate;
use miso_record::record::{Self, Record};
use std::type_name::{Self, TypeName};
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
const EWrongGate: vector<u8> = b"Seal identity names a different certificate gate";

#[error]
const EWrongCertificateType: vector<u8> =
    b"Record certificate type does not match the immutable gate";

#[error]
const EWrongRelease: vector<u8> = b"Record is a copy of a different release";

#[error]
const EInvalidNonceLength: vector<u8> = b"Seal identity nonce must be exactly 32 bytes";

// === Objects ===

/// Authority to add trusted certificate types without changing policy bytecode.
///
/// The capability is key-only so an external package cannot share or freeze it and
/// turn an immutable borrow into public authority.
public struct PolicyAdminCap has key {
    id: UID,
}

/// Immutable authorization for one exact certificate type.
///
/// The stored name uses original package IDs, so a compatible certificate-package
/// upgrade keeps the same identity. The gate itself is key-only and is always frozen
/// by this module before it reaches storage.
public struct CertificateGate has key {
    id: UID,
    certificate_type: TypeName,
}

// === Initialization and administration ===

fun init(ctx: &mut TxContext) {
    let sender = ctx.sender();
    transfer::transfer(PolicyAdminCap { id: object::new(ctx) }, sender);
    create_and_freeze_gate<Certificate>(ctx);
}

/// Add another trusted certificate type and freeze its gate permanently.
///
/// This is a non-public entry endpoint that requires the key-only admin capability.
/// Clients pin Miso's reviewed package and gate configuration. Future certificate-type
/// expansion happens by exercising this function with the current cap owner's input.
entry fun add_certificate_gate<T: drop + store>(
    _admin_cap: &PolicyAdminCap,
    ctx: &mut TxContext,
) {
    create_and_freeze_gate<T>(ctx)
}

/// Transfer policy administration to another address.
public fun transfer_admin_cap(admin_cap: PolicyAdminCap, recipient: address) {
    transfer::transfer(admin_cap, recipient)
}

fun new_gate<T: drop + store>(ctx: &mut TxContext): CertificateGate {
    CertificateGate {
        id: object::new(ctx),
        certificate_type: type_name::with_original_ids<T>(),
    }
}

fun create_and_freeze_gate<T: drop + store>(ctx: &mut TxContext) {
    transfer::freeze_object(new_gate<T>(ctx))
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

// === Views ===

public fun certificate_type(gate: &CertificateGate): TypeName {
    gate.certificate_type
}

// === Seal policy ===

/// Approve release-mix key access for the current owner of a trusted record.
///
/// This function is side-effect-free: both objects are immutable borrows and it
/// returns nothing. The `id` argument must remain first for Seal's `ValidPtb` parser.
entry fun seal_approve<T: drop + store>(
    id: vector<u8>,
    gate: &CertificateGate,
    record: &Record<T>,
) {
    assert_approved(id, gate, record)
}

fun assert_approved<T: drop + store>(
    id: vector<u8>,
    gate: &CertificateGate,
    record: &Record<T>,
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
    assert!(gate.certificate_type == type_name::with_original_ids<T>(), EWrongCertificateType);
    assert!(release_id == record.release_id(), EWrongRelease);
}

// === Test helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun add_certificate_gate_for_testing<T: drop + store>(
    admin_cap: &PolicyAdminCap,
    ctx: &mut TxContext,
) {
    add_certificate_gate<T>(admin_cap, ctx)
}

#[test_only]
public fun new_gate_for_testing<T: drop + store>(ctx: &mut TxContext): CertificateGate {
    new_gate<T>(ctx)
}

#[test_only]
public fun seal_approve_for_testing<T: drop + store>(
    id: vector<u8>,
    gate: &CertificateGate,
    record: &Record<T>,
) {
    seal_approve(id, gate, record)
}
