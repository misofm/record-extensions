// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_record_seal_policy::policy_tests;

use miso_record::record::{Self, Record};
use miso_record::settings;
use miso_record_seal_policy::policy::{Self, RecordGate};
use std::unit_test::{assert_eq, destroy};
use sui::test_scenario as ts;

/// Stand-in for a distribution package's module-controlled witness.
public struct DemoWitness() has drop;

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

fun new_record(release_id: ID, number: u64, ctx: &mut TxContext): Record {
    let (mut settings, settings_admin) = settings::new_for_testing(ctx);
    settings.authorize<DemoWitness>(&settings_admin);
    let mut parent = object::new(ctx);
    let record = record::mint(&mut parent, &settings, DemoWitness(), release_id, number);
    parent.delete();
    destroy(settings);
    destroy(settings_admin);
    record
}

fun approval_case(
    release_id: ID,
    ctx: &mut TxContext,
): (RecordGate, Record, vector<u8>) {
    let gate = policy::new_gate_for_testing(ctx);
    let record = new_record(release_id, 1, ctx);
    let identity = policy::release_mix_identity(object::id(&gate), release_id, nonce());
    (gate, record, identity)
}

// === Init and gate lifecycle ===

#[test]
fun init_freezes_exactly_one_record_gate() {
    let owner = @0xA;
    let mut scenario = ts::begin(owner);
    policy::init_for_testing(scenario.ctx());

    scenario.next_tx(owner);
    let gate = scenario.take_immutable<RecordGate>();
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
fun matching_gate_and_release_are_approved_without_mutation() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, identity) = approval_case(release_id, &mut ctx);
    let gate_id = object::id(&gate);
    let record_id = object::id(&record);

    policy::seal_approve_for_testing(identity, &gate, &record);

    assert_eq!(object::id(&gate), gate_id);
    assert_eq!(object::id(&record), record_id);
    assert_eq!(record.release_id(), release_id);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::EWrongGate, location = policy)]
fun identity_for_another_gate_is_rejected() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, _) = approval_case(release_id, &mut ctx);
    let identity = policy::release_mix_identity(id(@0xBAD), release_id, nonce());

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::EWrongRelease, location = policy)]
fun record_for_another_release_is_rejected() {
    let mut ctx = tx_context::dummy();
    let (gate, record, _) = approval_case(id(@0xBEEF), &mut ctx);
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
    let (gate, record, mut identity) = approval_case(release_id, &mut ctx);
    let _ = identity.pop_back();

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::ETrailingIdentityBytes, location = policy)]
fun trailing_identity_bytes_are_rejected() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, mut identity) = approval_case(release_id, &mut ctx);
    identity.push_back(0);

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::EUnsupportedSchema, location = policy)]
fun unknown_schema_is_rejected() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, mut identity) = approval_case(release_id, &mut ctx);
    *&mut identity[0] = 2;

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}

#[test, expected_failure(abort_code = policy::EWrongPolicyKind, location = policy)]
fun another_policy_kind_is_rejected() {
    let mut ctx = tx_context::dummy();
    let release_id = id(@0xBEEF);
    let (gate, record, mut identity) = approval_case(release_id, &mut ctx);
    *&mut identity[1] = 2;

    policy::seal_approve_for_testing(identity, &gate, &record);

    record.destroy();
    destroy(gate);
}
