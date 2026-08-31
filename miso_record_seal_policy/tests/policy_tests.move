// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_record_seal_policy::policy_tests;

use miso::release::{Self, Release, ReleaseAdminCap};
use miso::{test_helpers, track};
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

fun new_release(
    recording_ids: vector<ID>,
    ctx: &mut TxContext,
): (Release, ReleaseAdminCap) {
    let composition_id = test_helpers::fake_id(ctx);
    let target_release_id = test_helpers::fake_id(ctx);
    let split = 10000 / recording_ids.length();
    let tracks = recording_ids.map!(|recording_id| {
        track::new_for_testing(
            composition_id,
            recording_id,
            target_release_id,
            split as u16,
        )
    });
    release::new_for_testing("Policy release", tracks, ctx)
}

fun approval_case(
    recording_id: ID,
    ctx: &mut TxContext,
): (RecordGate, Record, Release, ReleaseAdminCap, vector<u8>) {
    let gate = policy::new_gate_for_testing(ctx);
    let (release, release_cap) = new_release(vector[recording_id], ctx);
    let record = new_record(object::id(&release), 1, ctx);
    let identity = policy::recording_session_identity(
        object::id(&gate),
        recording_id,
        nonce(),
    );
    (gate, record, release, release_cap, identity)
}

fun destroy_case(
    gate: RecordGate,
    record: Record,
    release: Release,
    release_cap: ReleaseAdminCap,
) {
    record.destroy();
    destroy(gate);
    destroy(release);
    destroy(release_cap);
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
fun recording_session_identity_matches_the_98_byte_golden_vector() {
    let actual = policy::recording_session_identity(id(@0x11), id(@0x22), nonce());
    let expected = vector[
        1, 1,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 17,
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
    let _ = policy::recording_session_identity(id(@0x11), id(@0x22), short_nonce);
}

// === Approval ===

#[test]
fun a_record_for_a_release_containing_the_recording_is_approved() {
    let mut ctx = tx_context::dummy();
    let recording_id = id(@0xBEEF);
    let (gate, record, release, release_cap, identity) = approval_case(recording_id, &mut ctx);
    let gate_id = object::id(&gate);
    let record_id = object::id(&record);

    policy::seal_approve_for_testing(identity, &gate, &record, &release);

    assert_eq!(object::id(&gate), gate_id);
    assert_eq!(object::id(&record), record_id);
    assert_eq!(record.release_id(), object::id(&release));
    destroy_case(gate, record, release, release_cap);
}

#[test]
fun the_same_recording_identity_works_through_distinct_releases() {
    let mut ctx = tx_context::dummy();
    let recording_id = id(@0xBEEF);
    let gate = policy::new_gate_for_testing(&mut ctx);
    let identity = policy::recording_session_identity(
        object::id(&gate),
        recording_id,
        nonce(),
    );
    let (first_release, first_cap) = new_release(vector[recording_id], &mut ctx);
    let first_record = new_record(object::id(&first_release), 1, &mut ctx);
    let (second_release, second_cap) = new_release(vector[recording_id], &mut ctx);
    let second_record = new_record(object::id(&second_release), 2, &mut ctx);

    policy::seal_approve_for_testing(identity, &gate, &first_record, &first_release);
    policy::seal_approve_for_testing(
        policy::recording_session_identity(object::id(&gate), recording_id, nonce()),
        &gate,
        &second_record,
        &second_release,
    );

    first_record.destroy();
    second_record.destroy();
    destroy(gate);
    destroy(first_release);
    destroy(first_cap);
    destroy(second_release);
    destroy(second_cap);
}

#[test, expected_failure(abort_code = policy::EWrongGate, location = policy)]
fun identity_for_another_gate_is_rejected() {
    let mut ctx = tx_context::dummy();
    let recording_id = id(@0xBEEF);
    let (gate, record, release, release_cap, _) = approval_case(recording_id, &mut ctx);
    let identity = policy::recording_session_identity(id(@0xBAD), recording_id, nonce());
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, release, release_cap);
}

#[test, expected_failure(abort_code = policy::EWrongRelease, location = policy)]
fun a_different_release_cannot_be_substituted_for_the_records_release() {
    let mut ctx = tx_context::dummy();
    let recording_id = id(@0xBEEF);
    let (gate, record, release, release_cap, identity) = approval_case(recording_id, &mut ctx);
    let (other_release, other_cap) = new_release(vector[recording_id], &mut ctx);
    policy::seal_approve_for_testing(identity, &gate, &record, &other_release);
    destroy_case(gate, record, release, release_cap);
    destroy(other_release);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = policy::ERecordingNotInRelease, location = policy)]
fun a_record_does_not_unlock_a_recording_outside_its_release() {
    let mut ctx = tx_context::dummy();
    let included_recording = id(@0xBEEF);
    let excluded_recording = id(@0xCAFE);
    let (gate, record, release, release_cap, _) = approval_case(included_recording, &mut ctx);
    let identity = policy::recording_session_identity(
        object::id(&gate),
        excluded_recording,
        nonce(),
    );
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, release, release_cap);
}

// === Malformed identities ===

#[test, expected_failure(abort_code = policy::EInvalidIdentityLength, location = policy)]
fun truncated_identity_is_rejected_before_parsing() {
    let mut ctx = tx_context::dummy();
    let (gate, record, release, release_cap, mut identity) = approval_case(id(@0xBEEF), &mut ctx);
    let _ = identity.pop_back();
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, release, release_cap);
}

#[test, expected_failure(abort_code = policy::ETrailingIdentityBytes, location = policy)]
fun trailing_identity_bytes_are_rejected() {
    let mut ctx = tx_context::dummy();
    let (gate, record, release, release_cap, mut identity) = approval_case(id(@0xBEEF), &mut ctx);
    identity.push_back(0);
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, release, release_cap);
}

#[test, expected_failure(abort_code = policy::EUnsupportedSchema, location = policy)]
fun unknown_schema_is_rejected() {
    let mut ctx = tx_context::dummy();
    let (gate, record, release, release_cap, mut identity) = approval_case(id(@0xBEEF), &mut ctx);
    *&mut identity[0] = 2;
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, release, release_cap);
}

#[test, expected_failure(abort_code = policy::EWrongPolicyKind, location = policy)]
fun another_policy_kind_is_rejected() {
    let mut ctx = tx_context::dummy();
    let (gate, record, release, release_cap, mut identity) = approval_case(id(@0xBEEF), &mut ctx);
    *&mut identity[1] = 2;
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, release, release_cap);
}
