// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module record_seal_policy::policy_tests;

use miso::composition::{Self, Composition, CompositionAdminCap};
use miso::recording::{Self, Recording, RecordingAdminCap};
use miso::release::{Self, Release, ReleaseAdminCap};
use miso::{test_helpers, track};
use miso_record::pressing::{Self, Pressing, PressingAdminCap};
use miso_record::record::{Self, Record};
use record_seal_policy::policy;
use std::unit_test::destroy;
use sui::clock;
use sui::sui::SUI;
use sui::test_scenario as ts;

public struct DemoWitness() has drop;
public struct CompositionShare() has drop;
public struct RecordingShare() has drop;

const EDITION: u16 = 1;
const PURCHASE_PRICE: u64 = 1_000;
const PURCHASE_TIMESTAMP_MS: u64 = 123_456;

fun release_identity(release_id: ID): vector<u8> {
    release_id.to_bytes()
}

fun track_member_identity(release_id: ID, track_idx: u8, member_id: ID): vector<u8> {
    let mut identity = release_id.to_bytes();
    identity.push_back(track_idx);
    identity.append(member_id.to_bytes());
    identity
}

fun policy_case(ctx: &mut TxContext): (
    Composition<CompositionShare>,
    CompositionAdminCap<CompositionShare>,
    Recording<RecordingShare, CompositionShare>,
    RecordingAdminCap<RecordingShare>,
    Release,
    ReleaseAdminCap,
    Record,
    Pressing,
    PressingAdminCap,
) {
    let (composition, composition_cap) =
        composition::new_for_testing<CompositionShare>("Policy composition", 1_500, ctx);
    let (recording, recording_cap) =
        recording::new_for_testing<RecordingShare, CompositionShare>(
            object::id(&composition),
            ctx,
        );
    let target_release_id = test_helpers::fake_id(ctx);
    let release_track = track::new_for_testing(
        object::id(&composition),
        object::id(&recording),
        target_release_id,
        10_000,
    );
    let (mut release, release_cap) =
        release::new_for_testing("Policy release", vector[release_track], ctx);
    let (mut pressing, pressing_cap) =
        pressing::new(&mut release, &release_cap, EDITION, option::some(1));
    pressing.authorize_distributor<DemoWitness>(&pressing_cap);
    let mut clock = clock::create_for_testing(ctx);
    clock.set_for_testing(PURCHASE_TIMESTAMP_MS);
    let record = pressing.mint<DemoWitness, SUI>(
        DemoWitness(),
        PURCHASE_PRICE,
        &clock,
        ctx,
    );
    clock.destroy_for_testing();

    (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    )
}

fun destroy_case(
    composition: Composition<CompositionShare>,
    composition_cap: CompositionAdminCap<CompositionShare>,
    recording: Recording<RecordingShare, CompositionShare>,
    recording_cap: RecordingAdminCap<RecordingShare>,
    release: Release,
    release_cap: ReleaseAdminCap,
    record: Record,
    pressing: Pressing,
    pressing_cap: PressingAdminCap,
) {
    record.destroy();
    destroy(composition);
    destroy(composition_cap);
    destroy(recording);
    destroy(recording_cap);
    destroy(release);
    destroy(release_cap);
    destroy(pressing);
    destroy(pressing_cap);
}

#[test]
fun a_record_approves_its_release() {
    let mut ctx = tx_context::dummy();
    let (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    ) = policy_case(&mut ctx);

    policy::seal_approve_release_for_testing(
        release_identity(object::id(&release)),
        &record,
        &release,
    );

    destroy_case(
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    );
}

#[test]
fun a_record_approves_the_recording_at_the_selected_track() {
    let mut ctx = tx_context::dummy();
    let (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    ) = policy_case(&mut ctx);

    policy::seal_approve_recording_for_testing(
        track_member_identity(object::id(&release), 0, object::id(&recording)),
        &record,
        &release,
        &recording,
    );

    destroy_case(
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    );
}

#[test]
fun a_record_approves_the_composition_at_the_selected_track() {
    let mut ctx = tx_context::dummy();
    let (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    ) = policy_case(&mut ctx);

    policy::seal_approve_composition_for_testing(
        track_member_identity(object::id(&release), 0, object::id(&composition)),
        &record,
        &release,
        &composition,
    );

    destroy_case(
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    );
}

#[test, expected_failure(abort_code = policy::EInvalidTrackIndex, location = policy)]
fun a_track_index_outside_the_release_is_rejected() {
    let mut ctx = tx_context::dummy();
    let (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    ) = policy_case(&mut ctx);
    policy::seal_approve_composition_for_testing(
        track_member_identity(object::id(&release), 1, object::id(&composition)),
        &record,
        &release,
        &composition,
    );
    destroy_case(
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    );
}

/// Model the object inputs used by a Seal approval PTB across transactions:
/// the requester owns the Record while the Release and Recordings are shared.
/// Supplying a different Recording object than the one named by the selected
/// track must still abort.
#[test, expected_failure(abort_code = policy::EWrongRecording, location = policy)]
fun an_owner_ptb_cannot_substitute_the_wrong_shared_recording() {
    let owner = @0xA;
    let mut scenario = ts::begin(owner);
    let (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    ) = policy_case(scenario.ctx());
    let (wrong_recording, wrong_recording_cap) =
        recording::new_for_testing<RecordingShare, CompositionShare>(
            object::id(&composition),
            scenario.ctx(),
        );
    let release_id = object::id(&release);
    let recording_id = object::id(&recording);
    let wrong_recording_id = object::id(&wrong_recording);
    let identity = track_member_identity(release_id, 0, recording_id);

    let clock = clock::create_for_testing(scenario.ctx());
    composition.publish(&composition_cap, &clock);
    recording.publish(&recording_cap, &clock);
    wrong_recording.publish(&wrong_recording_cap, &clock);
    release.publish(&release_cap, &clock);
    clock.destroy_for_testing();
    transfer::public_transfer(record, owner);
    destroy(composition_cap);
    destroy(recording_cap);
    destroy(wrong_recording_cap);
    destroy(release_cap);
    destroy(pressing);
    destroy(pressing_cap);

    scenario.next_tx(owner);
    let record = scenario.take_from_sender<Record>();
    let release = scenario.take_shared_by_id<Release>(release_id);
    let wrong_recording = scenario
        .take_shared_by_id<Recording<RecordingShare, CompositionShare>>(wrong_recording_id);

    policy::seal_approve_recording_for_testing(
        identity,
        &record,
        &release,
        &wrong_recording,
    );

    // Unreachable after the expected abort, but required for resource safety.
    scenario.return_to_sender(record);
    ts::return_shared(release);
    ts::return_shared(wrong_recording);
    scenario.end();
}

/// Model a Composition approval PTB with an owned Record and shared inputs.
/// The identity names the Composition on the selected track, but the supplied
/// Composition object is a different shared object.
#[test, expected_failure(abort_code = policy::EWrongComposition, location = policy)]
fun an_owner_ptb_cannot_substitute_the_wrong_shared_composition() {
    let owner = @0xA;
    let mut scenario = ts::begin(owner);
    let (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    ) = policy_case(scenario.ctx());
    let (wrong_composition, wrong_composition_cap) =
        composition::new_for_testing<CompositionShare>(
            "Wrong composition",
            1_500,
            scenario.ctx(),
        );
    let release_id = object::id(&release);
    let composition_id = object::id(&composition);
    let wrong_composition_id = object::id(&wrong_composition);
    let identity = track_member_identity(release_id, 0, composition_id);

    let clock = clock::create_for_testing(scenario.ctx());
    composition.publish(&composition_cap, &clock);
    wrong_composition.publish(&wrong_composition_cap, &clock);
    recording.publish(&recording_cap, &clock);
    release.publish(&release_cap, &clock);
    clock.destroy_for_testing();
    transfer::public_transfer(record, owner);
    destroy(composition_cap);
    destroy(wrong_composition_cap);
    destroy(recording_cap);
    destroy(release_cap);
    destroy(pressing);
    destroy(pressing_cap);

    scenario.next_tx(owner);
    let record = scenario.take_from_sender<Record>();
    let release = scenario.take_shared_by_id<Release>(release_id);
    let wrong_composition =
        scenario.take_shared_by_id<Composition<CompositionShare>>(wrong_composition_id);

    policy::seal_approve_composition_for_testing(
        identity,
        &record,
        &release,
        &wrong_composition,
    );

    // Unreachable after the expected abort, but required for resource safety.
    scenario.return_to_sender(record);
    ts::return_shared(release);
    ts::return_shared(wrong_composition);
    scenario.end();
}

/// Model a Release approval PTB with an owned Record and shared Releases. The
/// supplied Release matches the identity but is not the Release named by the
/// Record.
#[test, expected_failure(abort_code = policy::EWrongRelease, location = policy)]
fun an_owner_ptb_cannot_substitute_the_wrong_shared_release() {
    let owner = @0xA;
    let mut scenario = ts::begin(owner);
    let (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    ) = policy_case(scenario.ctx());
    let wrong_track = track::new_for_testing(
        object::id(&composition),
        object::id(&recording),
        test_helpers::fake_id(scenario.ctx()),
        10_000,
    );
    let (wrong_release, wrong_release_cap) =
        release::new_for_testing("Wrong release", vector[wrong_track], scenario.ctx());
    let wrong_release_id = object::id(&wrong_release);
    let identity = release_identity(wrong_release_id);

    let clock = clock::create_for_testing(scenario.ctx());
    composition.publish(&composition_cap, &clock);
    recording.publish(&recording_cap, &clock);
    release.publish(&release_cap, &clock);
    wrong_release.publish(&wrong_release_cap, &clock);
    clock.destroy_for_testing();
    transfer::public_transfer(record, owner);
    destroy(composition_cap);
    destroy(recording_cap);
    destroy(release_cap);
    destroy(wrong_release_cap);
    destroy(pressing);
    destroy(pressing_cap);

    scenario.next_tx(owner);
    let record = scenario.take_from_sender<Record>();
    let wrong_release = scenario.take_shared_by_id<Release>(wrong_release_id);

    policy::seal_approve_release_for_testing(identity, &record, &wrong_release);

    // Unreachable after the expected abort, but required for resource safety.
    scenario.return_to_sender(record);
    ts::return_shared(wrong_release);
    scenario.end();
}

#[test, expected_failure(abort_code = policy::EInvalidIdentityLength, location = policy)]
fun a_release_identity_with_trailing_bytes_is_rejected() {
    let mut ctx = tx_context::dummy();
    let (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    ) = policy_case(&mut ctx);
    let mut identity = release_identity(object::id(&release));
    identity.push_back(0);
    policy::seal_approve_release_for_testing(identity, &record, &release);
    destroy_case(
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    );
}

#[test, expected_failure(
    abort_code = policy::EInvalidIdentityLength,
    location = policy,
)]
fun a_truncated_track_member_identity_is_rejected() {
    let mut ctx = tx_context::dummy();
    let (
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    ) = policy_case(&mut ctx);
    let mut identity =
        track_member_identity(object::id(&release), 0, object::id(&recording));
    let _ = identity.pop_back();
    policy::seal_approve_recording_for_testing(identity, &record, &release, &recording);
    destroy_case(
        composition,
        composition_cap,
        recording,
        recording_cap,
        release,
        release_cap,
        record,
        pressing,
        pressing_cap,
    );
}
