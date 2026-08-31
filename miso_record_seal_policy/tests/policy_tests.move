// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_record_seal_policy::policy_tests;

use miso_pressing::certificate::Certificate;
use miso_pressing::listing;
use miso_pressing::pressing;
use miso_record::record::{Self, Record};
use miso_record_seal_policy::policy::{Self, CertificateGate, PolicyAdminCap};
use std::type_name;
use std::unit_test::{assert_eq, destroy};
use sui::balance;
use sui::clock;
use sui::sui::SUI;
use sui::test_scenario as ts;

public struct DemoCertificate(u64) has drop, store;
public struct OtherCertificate has drop, store {}

fun id(value: address): ID {
    object::id_from_address(value)
}

fun nonce(): vector<u8> {
    vector[
        0, 1, 2, 3, 4, 5, 6, 7,
        8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23,
        24, 25, 26, 27, 28, 29, 30, 31,
    ]
}

fun new_record<T: drop + store>(
    certificate: T,
    release_id: ID,
    number: u64,
    ctx: &mut TxContext,
): Record<T> {
    let mut parent = object::new(ctx);
    let record = record::new(&mut parent, certificate, release_id, number);
    parent.delete();
    record
}

fun approval_case<T: drop + store>(
    certificate: T,
    release_id: ID,
    ctx: &mut TxContext,
): (CertificateGate, Record<T>, vector<u8>) {
    let gate = policy::new_gate_for_testing<T>(ctx);
    let record = new_record(certificate, release_id, 1, ctx);
    let identity = policy::release_mix_identity(object::id(&gate), release_id, nonce());
    (gate, record, identity)
}

// === Init and gate lifecycle ===

#[test]
fun init_transfers_the_admin_cap_and_freezes_the_pressing_gate() {
    let owner = @0xA;
    let mut scenario = ts::begin(owner);
    policy::init_for_testing(scenario.ctx());

    scenario.next_tx(owner);
    assert!(scenario.has_most_recent_for_sender<PolicyAdminCap>());
    let admin_cap = scenario.take_from_sender<PolicyAdminCap>();
    let gate = scenario.take_immutable<CertificateGate>();
    assert_eq!(
        policy::certificate_type(&gate),
        type_name::with_original_ids<Certificate>(),
    );

    scenario.return_to_sender(admin_cap);
    ts::return_immutable(gate);
    scenario.end();
}

#[test]
fun admin_can_add_and_freeze_a_gate_later() {
    let owner = @0xA;
    let mut scenario = ts::begin(owner);
    policy::init_for_testing(scenario.ctx());

    scenario.next_tx(owner);
    let admin_cap = scenario.take_from_sender<PolicyAdminCap>();
    policy::add_certificate_gate_for_testing<DemoCertificate>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(owner);
    let gate = scenario.take_immutable<CertificateGate>();
    assert_eq!(
        policy::certificate_type(&gate),
        type_name::with_original_ids<DemoCertificate>(),
    );
    ts::return_immutable(gate);
    scenario.end();
}

#[test]
fun transferred_admin_cap_can_add_a_gate() {
    let first_admin = @0xA;
    let next_admin = @0xB;
    let mut scenario = ts::begin(first_admin);
    policy::init_for_testing(scenario.ctx());

    scenario.next_tx(first_admin);
    let admin_cap = scenario.take_from_sender<PolicyAdminCap>();
    policy::transfer_admin_cap(admin_cap, next_admin);

    scenario.next_tx(next_admin);
    let admin_cap = scenario.take_from_sender<PolicyAdminCap>();
    policy::add_certificate_gate_for_testing<OtherCertificate>(&admin_cap, scenario.ctx());
    scenario.return_to_sender(admin_cap);

    scenario.next_tx(next_admin);
    let gate = scenario.take_immutable<CertificateGate>();
    assert_eq!(
        policy::certificate_type(&gate),
        type_name::with_original_ids<OtherCertificate>(),
    );
    ts::return_immutable(gate);
    scenario.end();
}

// === Canonical identity ===

#[test]
fun release_mix_identity_matches_the_98_byte_golden_vector() {
    let actual = policy::release_mix_identity(id(@0x11), id(@0x22), nonce());
    let expected = vector[
        1, 1,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 17,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34,
        0, 1, 2, 3, 4, 5, 6, 7,
        8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23,
        24, 25, 26, 27, 28, 29, 30, 31,
    ];
    assert_eq!(actual.length(), 98);
    assert_eq!(actual, expected);
}

#[test, expected_failure(abort_code = policy::EInvalidNonceLength, location = policy)]
fun identity_builder_rejects_a_31_byte_nonce() {
    let mut short_nonce = nonce();
    let _ = short_nonce.pop_back();
    let _ = policy::release_mix_identity(id(@0x11), id(@0x22), short_nonce);
}

// === Approval ===

#[test]
fun pressing_gate_approves_an_actual_pressed_record() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let clock = clock::create_for_testing(&mut ctx);
    let (mut pressing, admin_cap) = pressing::new_for_testing(release_id, &mut ctx);
    let mut listing = listing::new_for_testing<SUI>(
        release_id,
        object::id(&pressing),
        listing::new_fixed_price(0),
        listing::new_enabled_state(),
        &mut ctx,
    );
    let record = listing.buy(&mut pressing, balance::zero<SUI>(), &clock, &ctx);
    let gate = policy::new_gate_for_testing<Certificate>(&mut ctx);
    let identity = policy::release_mix_identity(object::id(&gate), release_id, nonce());

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
    listing.destroy_for_testing();
    pressing.destroy_for_testing(admin_cap);
    clock.destroy_for_testing();
}

#[test]
fun matching_gate_type_id_and_release_are_approved_without_mutation() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, identity) = approval_case(DemoCertificate(42), release_id, &mut ctx);
    let gate_id = object::id(&gate);
    let record_id = object::id(&record);

    policy::seal_approve_for_testing(identity, &gate, &record);

    assert_eq!(object::id(&gate), gate_id);
    assert_eq!(object::id(&record), record_id);
    assert_eq!(record.release_id(), release_id);
    assert_eq!(record.certificate().0, 42);
    assert_eq!(
        policy::certificate_type(&gate),
        type_name::with_original_ids<DemoCertificate>(),
    );

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::EWrongCertificateType, location = policy)]
fun gate_rejects_another_certificate_type() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let gate = policy::new_gate_for_testing<DemoCertificate>(&mut ctx);
    let record = new_record(OtherCertificate {}, release_id, 1, &mut ctx);
    let identity = policy::release_mix_identity(object::id(&gate), release_id, nonce());

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::EWrongGate, location = policy)]
fun identity_for_another_gate_is_rejected() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, _) = approval_case(DemoCertificate(1), release_id, &mut ctx);
    let identity = policy::release_mix_identity(id(@0xBAD), release_id, nonce());

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::EWrongRelease, location = policy)]
fun record_for_another_release_is_rejected() {
    let mut ctx = tx_context::dummy();
    let (gate, record, _) = approval_case(DemoCertificate(1), id(@0xBEEF), &mut ctx);
    let identity = policy::release_mix_identity(object::id(&gate), id(@0xCAFE), nonce());

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

// === Malformed identities ===

#[test, expected_failure(abort_code = policy::EInvalidIdentityLength, location = policy)]
fun truncated_identity_is_rejected_before_parsing() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, mut identity) = approval_case(DemoCertificate(1), release_id, &mut ctx);
    let _ = identity.pop_back();

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::ETrailingIdentityBytes, location = policy)]
fun trailing_identity_bytes_are_rejected() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, mut identity) = approval_case(DemoCertificate(1), release_id, &mut ctx);
    identity.push_back(0);

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::EUnsupportedSchema, location = policy)]
fun unknown_schema_is_rejected() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, mut identity) = approval_case(DemoCertificate(1), release_id, &mut ctx);
    *&mut identity[0] = 2;

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::EWrongPolicyKind, location = policy)]
fun another_policy_kind_is_rejected() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, mut identity) = approval_case(DemoCertificate(1), release_id, &mut ctx);
    *&mut identity[1] = 2;

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}
