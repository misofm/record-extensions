// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module miso_record_seal_policy::policy_tests;

use miso::release::{Self, Release, ReleaseAdminCap};
use miso::{test_helpers, track};
use miso_record::pressing::{Self, Pressing, PressingAdminCap};
use miso_record::record::{Self, Record};
use miso_record_seal_policy::policy::{Self, RecordGate};
use std::{type_name, unit_test::{assert_eq, destroy}};
use sui::clock;
use sui::sui::SUI;
use sui::test_scenario as ts;

/// Stand-in for a distribution package's module-controlled witness.
public struct DemoWitness() has drop;

const EDITION: u16 = 1;
const PURCHASE_PRICE: u64 = 1_000;
const PURCHASE_TIMESTAMP_MS: u64 = 123_456;

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

fun new_record(
    release: &mut Release,
    release_cap: &ReleaseAdminCap,
    ctx: &mut TxContext,
): (Record, Pressing, PressingAdminCap) {
    let (mut pressing, pressing_cap) = pressing::new(
        release,
        release_cap,
        EDITION,
        option::some(1),
    );
    pressing.authorize_distributor<DemoWitness>(&pressing_cap);
    let mut clk = clock::create_for_testing(ctx);
    clk.set_for_testing(PURCHASE_TIMESTAMP_MS);
    let record = pressing.mint<DemoWitness, SUI>(
        DemoWitness(),
        PURCHASE_PRICE,
        &clk,
        ctx,
    );
    clk.destroy_for_testing();
    (record, pressing, pressing_cap)
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
): (
    RecordGate,
    Record,
    Pressing,
    PressingAdminCap,
    Release,
    ReleaseAdminCap,
    vector<u8>,
) {
    let gate = policy::new_gate_for_testing(ctx);
    let (mut release, release_cap) = new_release(vector[recording_id], ctx);
    let (record, pressing, pressing_cap) = new_record(&mut release, &release_cap, ctx);
    let identity = policy::recording_session_identity(
        object::id(&gate),
        recording_id,
        nonce(),
    );
    (
        gate,
        record,
        pressing,
        pressing_cap,
        release,
        release_cap,
        identity,
    )
}

fun destroy_case(
    gate: RecordGate,
    record: Record,
    pressing: Pressing,
    pressing_cap: PressingAdminCap,
    release: Release,
    release_cap: ReleaseAdminCap,
) {
    record.destroy();
    destroy(gate);
    destroy(pressing);
    destroy(pressing_cap);
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

#[test, expected_failure(abort_code = policy::EOwnershipUnprovable, location = policy)]
fun a_matching_recording_session_fails_closed_without_an_ownership_proof() {
    let mut ctx = tx_context::dummy();
    let recording_id = id(@0xBEEF);
    let (gate, record, pressing, pressing_cap, release, release_cap, identity) =
        approval_case(recording_id, &mut ctx);

    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, pressing, pressing_cap, release, release_cap);
}

#[test]
fun identity_validation_accepts_the_same_recording_through_distinct_releases() {
    let mut ctx = tx_context::dummy();
    let purchaser = ctx.sender();
    let recording_id = id(@0xBEEF);
    let gate = policy::new_gate_for_testing(&mut ctx);
    let identity = policy::recording_session_identity(
        object::id(&gate),
        recording_id,
        nonce(),
    );
    let (mut first_release, first_cap) = new_release(vector[recording_id], &mut ctx);
    let (first_record, first_pressing, first_pressing_cap) =
        new_record(&mut first_release, &first_cap, &mut ctx);
    let (mut second_release, second_cap) = new_release(vector[recording_id], &mut ctx);
    let (second_record, second_pressing, second_pressing_cap) =
        new_record(&mut second_release, &second_cap, &mut ctx);

    assert_eq!(first_record.release_id(), object::id(&first_release));
    assert_eq!(first_record.pressing_id(), object::id(&first_pressing));
    assert_eq!(first_record.edition(), EDITION);
    assert_eq!(first_record.number(), 1);
    assert_eq!(first_record.purchase_currency(), type_name::with_defining_ids<SUI>());
    assert_eq!(first_record.purchase_price(), PURCHASE_PRICE);
    assert_eq!(first_record.purchased_by(), purchaser);
    assert_eq!(first_record.purchased_timestamp_ms(), PURCHASE_TIMESTAMP_MS);
    assert_eq!(first_pressing.release_id(), object::id(&first_release));
    assert_eq!(first_pressing.edition(), EDITION);
    assert_eq!(first_pressing.supply(), 1);
    assert_eq!(first_pressing.max_supply(), option::some(1));
    assert!(first_pressing.is_distributor_authorized<DemoWitness>());

    policy::validate_identity_for_testing(identity, &gate, &first_record, &first_release);
    policy::validate_identity_for_testing(
        policy::recording_session_identity(object::id(&gate), recording_id, nonce()),
        &gate,
        &second_record,
        &second_release,
    );

    first_record.destroy();
    second_record.destroy();
    destroy(gate);
    destroy(first_pressing);
    destroy(first_pressing_cap);
    destroy(first_release);
    destroy(first_cap);
    destroy(second_pressing);
    destroy(second_pressing_cap);
    destroy(second_release);
    destroy(second_cap);
}

#[test, expected_failure(abort_code = policy::EOwnershipUnprovable, location = policy)]
fun a_non_owner_cannot_use_a_shared_record_to_bypass_the_disabled_policy() {
    let owner = @0xA;
    let attacker = @0xB;
    let recording_id = id(@0xBEEF);
    let mut scenario = ts::begin(owner);
    let gate = policy::new_gate_for_testing(scenario.ctx());
    let (mut release, release_cap) = new_release(vector[recording_id], scenario.ctx());
    let (record, pressing, pressing_cap) =
        new_record(&mut release, &release_cap, scenario.ctx());
    let identity = policy::recording_session_identity(
        object::id(&gate),
        recording_id,
        nonce(),
    );
    transfer::public_share_object(record);

    scenario.next_tx(attacker);
    let record = scenario.take_shared<Record>();
    policy::seal_approve_for_testing(identity, &gate, &record, &release);

    ts::return_shared(record);
    destroy(gate);
    destroy(pressing);
    destroy(pressing_cap);
    destroy(release);
    destroy(release_cap);
    scenario.end();
}

#[test, expected_failure(abort_code = policy::EWrongGate, location = policy)]
fun identity_for_another_gate_is_rejected() {
    let mut ctx = tx_context::dummy();
    let recording_id = id(@0xBEEF);
    let (gate, record, pressing, pressing_cap, release, release_cap, _) =
        approval_case(recording_id, &mut ctx);
    let identity = policy::recording_session_identity(id(@0xBAD), recording_id, nonce());
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, pressing, pressing_cap, release, release_cap);
}

#[test, expected_failure(abort_code = policy::EWrongRelease, location = policy)]
fun a_different_release_cannot_be_substituted_for_the_records_release() {
    let mut ctx = tx_context::dummy();
    let recording_id = id(@0xBEEF);
    let (gate, record, pressing, pressing_cap, release, release_cap, identity) =
        approval_case(recording_id, &mut ctx);
    let (other_release, other_cap) = new_release(vector[recording_id], &mut ctx);
    policy::seal_approve_for_testing(identity, &gate, &record, &other_release);
    destroy_case(gate, record, pressing, pressing_cap, release, release_cap);
    destroy(other_release);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = policy::ERecordingNotInRelease, location = policy)]
fun a_record_does_not_unlock_a_recording_outside_its_release() {
    let mut ctx = tx_context::dummy();
    let included_recording = id(@0xBEEF);
    let excluded_recording = id(@0xCAFE);
    let (gate, record, pressing, pressing_cap, release, release_cap, _) =
        approval_case(included_recording, &mut ctx);
    let identity = policy::recording_session_identity(
        object::id(&gate),
        excluded_recording,
        nonce(),
    );
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, pressing, pressing_cap, release, release_cap);
}

// === Malformed identities ===

#[test, expected_failure(abort_code = policy::EInvalidIdentityLength, location = policy)]
fun truncated_identity_is_rejected_before_parsing() {
    let mut ctx = tx_context::dummy();
    let (gate, record, pressing, pressing_cap, release, release_cap, mut identity) =
        approval_case(id(@0xBEEF), &mut ctx);
    let _ = identity.pop_back();
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, pressing, pressing_cap, release, release_cap);
}

#[test, expected_failure(abort_code = policy::ETrailingIdentityBytes, location = policy)]
fun trailing_identity_bytes_are_rejected() {
    let mut ctx = tx_context::dummy();
    let (gate, record, pressing, pressing_cap, release, release_cap, mut identity) =
        approval_case(id(@0xBEEF), &mut ctx);
    identity.push_back(0);
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, pressing, pressing_cap, release, release_cap);
}

#[test, expected_failure(abort_code = policy::EUnsupportedSchema, location = policy)]
fun unknown_schema_is_rejected() {
    let mut ctx = tx_context::dummy();
    let (gate, record, pressing, pressing_cap, release, release_cap, mut identity) =
        approval_case(id(@0xBEEF), &mut ctx);
    *&mut identity[0] = 2;
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, pressing, pressing_cap, release, release_cap);
}

#[test, expected_failure(abort_code = policy::EWrongPolicyKind, location = policy)]
fun another_policy_kind_is_rejected() {
    let mut ctx = tx_context::dummy();
    let (gate, record, pressing, pressing_cap, release, release_cap, mut identity) =
        approval_case(id(@0xBEEF), &mut ctx);
    *&mut identity[1] = 2;
    policy::seal_approve_for_testing(identity, &gate, &record, &release);
    destroy_case(gate, record, pressing, pressing_cap, release, release_cap);
}
